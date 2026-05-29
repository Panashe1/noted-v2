Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users

  root "users#home"

  resources :tracks, only: [:index, :show]

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
  end

  get "/discover", to: "recommendations#index", as: :recommendations
  get "/search",   to: "users#search",          as: :user_search

  # iTunes search & preview (modal AJAX endpoints)
  get "/music/search",  to: "music#search",  as: :music_search
  get "/music/preview", to: "music#preview", as: :music_preview
end
