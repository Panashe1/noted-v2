# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"

  # Albums
  resources :albums, only: [:index, :show]

  # Listen logs
  resources :listen_logs, only: [:create, :edit, :update, :destroy] do
    collection do
      post :assist_review  # AI review assistant endpoint
    end
  end

  # User profiles — /u/panashe
  scope "/u" do
    get "/:username", to: "users#show", as: :user
  end

  # Follow / unfollow
  scope "/u/:username" do
    post   "/follow",   to: "follows#create",  as: :follow_user
    delete "/follow",   to: "follows#destroy", as: :unfollow_user
  end

  # AI recommendations
  get "/discover", to: "recommendations#index", as: :recommendations
end
