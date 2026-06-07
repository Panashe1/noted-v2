Rails.application.routes.draw do
  # Health check stays outside the locale scope — probes hit it without a locale.
  get "up" => "rails/health#show", as: :rails_health_check

  # Optional locale prefix. The default locale (:en) is unprefixed (/albums);
  # other locales are prefixed (/es/albums). The constraint stops a normal path
  # segment like "albums" from being parsed as a locale.
  scope "(:locale)", locale: /en|es/ do
    devise_for :users

    root "users#home"

    resources :tracks, only: [:index, :show] do
      collection do
        get :from_itunes
      end
    end

    resources :albums, only: [:index, :show] do
      collection do
        get :from_itunes
      end
    end

    resources :track_logs, only: [:create, :edit, :update, :destroy]

    resources :listen_logs, only: [:create, :edit, :update, :destroy] do
      collection do
        post :assist_review
      end
    end

    scope "/u" do
      get "/:username", to: "users#show", as: :user
    end

    scope "/u/:username" do
      post   "/follow",     to: "follows#create",      as: :follow_user
      delete "/follow",     to: "follows#destroy",     as: :unfollow_user
      get    "/following",  to: "users#following",     as: :user_following
      get    "/followers",  to: "users#followers",     as: :user_followers
      get    "/settings",   to: "users#settings",      as: :user_settings
      patch  "/settings",   to: "users#update_settings"
    end

    get "/discover", to: "recommendations#index", as: :recommendations
    get "/search",   to: "users#search",          as: :user_search

    # iTunes search & preview (modal AJAX endpoints)
    get "/music/search",  to: "music#search",  as: :music_search
    get "/music/preview", to: "music#preview", as: :music_preview
  end
end
