module FFXIV
  class Application < Sinatra::Base
    set :root, Root.to_s
    set :method_override, true
    set :logging, true
    set :erb, :trim => '-'
    use Rack::Session::Cookie, :secret => YAML.load_file(Root + "config" + "secret.yml").to_s

    opts = {:required => [], :optional => []}
    use OmniAuth::Strategies::OpenID, OpenID::Store::Filesystem.new('/tmp'), opts
    use OmniAuth::Strategies::OpenID, OpenID::Store::Filesystem.new('/tmp'), opts.merge(:name => 'google', :identifier => 'https://www.google.com/accounts/o8/id')

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def authenticate!(options = nil)
        if current_user.nil?
          if options.nil?
            session['return_to'] = request.path_info
            redirect '/login'
          elsif !options[:redirect]
            halt 401
          end
        end
      end

      def current_user
        unless @current_user
          @current_user = session['user_id'] ? User[session['user_id']] : nil
        end
        @current_user
      end

      def current_character
        if @current_character.nil? && current_user
          if session['character_id']
            @current_character = current_user.characters_dataset[session['character_id']]
          else
            @current_character = current_user.characters_dataset.first
            session['character_id'] = @current_character.id
          end
        end
        @current_character
      end

      def error_messages_for(object)
        return ""   if object.nil? || object.errors.empty?

        retval = "<div class='errors'><h3>Errors detected:</h3><ul>"
        object.errors.each do |(attr, messages)|
          messages.each do |message|
            retval += "<li>"
            retval += attr.to_s.tr("_", " ").capitalize + " " if attr != :base
            retval += "#{message}</li>"
          end
        end
        retval += "</ul></div><div class='clear'></div>"

        retval
      end
    end

    get '/' do
      authenticate!
      @all_items = Item.eager_graph(:notes).filter({:notes__character_id => nil} | {:notes__character_id => current_character.id}).order(:items__position, :items__name).all
      @owned_items = Item.eager_graph(:notes).filter({:notes__character_id => current_character.id, :notes__owned => true}).order(:items__position, :items__id).all
      @categories = Category.order(:row_id, :name).all
      erb :index
    end

    get '/items.json' do
      authenticate!(:redirect => false)
      content_type 'application/json'

      ds = Item.eager_graph(:notes).filter({:notes__character_id => nil} | ({:notes__character_id => current_character.id} & ~{:notes__owned => true})).order(:items__name)
      if params['term']
        ds = ds.filter(:items__name.like("#{params['term']}%"))
      end

      ds.all.collect do |item|
        note = item.notes.first
        {'label' => item.name, 'id' => item.id, 'category_id' => item.category_id, 'rank' => item.optimal_rank, 'note' => note.note}
      end.to_json
    end

    post '/items/:id/prices.json' do
      authenticate!(:redirect => false)
      content_type 'application/json'

      item = Item[params[:id]]
      halt 404  if item.nil?

      price = Price.new(params['price'])
      price.item = item
      price.user = current_user
      if price.valid?
        price.save
        {'price' => {:id => price.id, :value => price.value}}.to_json
      else
        {'errors' => price.errors}.to_json
      end
    end

    post '/notes.json' do
      authenticate!(:redirect => false)
      content_type 'application/json'

      note = Note.new(params['note'])
      note.character = current_character
      if note.valid?
        note.save
        item = note.item
        price = item.prices.first
        {'note' => {'id' => note.id, 'item' => item.name, 'category' => item.category.name, 'note' => note.note || '', 'rank' => item.optimal_rank || '', 'item_id' => note.item_id, 'price' => price ? price.value : nil}}.to_json
      else
        {'errors' => note.errors}.to_json
      end
    end

    put '/notes/:id.json' do
      authenticate!(:redirect => false)
      content_type 'application/json'

      note = Note[params[:id]]
      halt 404  if note.nil?

      note.update(params[:note])
      "true"
    end

    get '/prices/edit' do
      @items = Item.eager_graph(:notes).filter({:notes__character_id => current_character.id, :notes__owned => true}).order(:items__category_id, :items__position, :items__id).all
      erb :prices
    end

    post '/prices' do
      params[:prices].each_pair do |item_id, value|
        next  if value !~ /^\d+$/
        Price.create(:item_id => item_id, :user_id => current_user.id, :value => value)
      end
      redirect '/'
    end

    get '/login' do
      if current_user
        redirect '/'
      else
        erb :login
      end
    end

    get '/signup' do
      redirect '/login' if !session['omniauth']

      @user = User.new
      @characters = [Character.new]
      erb :signup
    end

    post '/signup' do
      redirect '/login' if !session['omniauth']

      auth = session['omniauth']
      @user = User.new(params['user'])
      @user.provider = auth['provider']
      @user.uid = auth['uid']

      if @user.valid? && @user.save
        session.delete('omniauth')
        session['user_id'] = @user.id
        redirect '/'
      else
        @characters = @user.characters
        @characters = [Character.new] if @characters.empty?
        erb :signup
      end
    end

    post '/auth/:provider/callback' do
      auth = request.env['omniauth.auth']
      user = User[:provider => auth['provider'], :uid => auth['uid']]
      if user
        session['user_id'] = user.id
        redirect '/'
      else
        session['omniauth'] = auth
        redirect '/signup'
      end
    end
  end
end
