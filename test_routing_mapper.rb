# frozen_string_literal: true

require "erb"
require "abstract_unit"
require "controller/fake_controllers"
require "active_support/messages/rotation_configuration"

class TestRoutingMapper < ActionDispatch::IntegrationTest
  SprocketsApp = lambda { |env|
    [200, { "Content-Type" => "text/html" }, ["javascripts"]]
  }

  class IpRestrictor
    def self.matches?(request)
      /192\.168\.1\.1\d\d/.match?(request.ip)
    end
  end

  class GrumpyRestrictor
    def self.matches?(request)
      false
    end
  end

  class YoutubeFavoritesRedirector
    def self.call(params, request)
      "http://www.youtube.com/watch?v=#{params[:youtube_id]}"
    end
  end

  def test_logout
    draw do
      controller :sessions do
        delete "logout" => :destroy
      end
    end

    delete "/logout"
    assert_equal "sessions#destroy", @response.body

    assert_equal "/logout", logout_path
    assert_equal "/logout", url_for(controller: "sessions", action: "destroy", only_path: true)
  end

  def test_login
    draw do
      default_url_options host: "rubyonrails.org"

      controller :sessions do
        get  "login" => :new
        post "login" => :create
      end
    end

    get "/login"
    assert_equal "sessions#new", @response.body
    assert_equal "/login", login_path

    post "/login"
    assert_equal "sessions#create", @response.body

    assert_equal "/login", url_for(controller: "sessions", action: "create", only_path: true)
    assert_equal "/login", url_for(controller: "sessions", action: "new", only_path: true)

    assert_equal "http://rubyonrails.org/login", url_for(controller: "sessions", action: "create")
    assert_equal "http://rubyonrails.org/login", login_url
  end

  def test_login_redirect
    draw do
      get "account/login", to: redirect("/login")
    end

    get "/account/login"
    verify_redirect "http://www.example.com/login"
  end

  def test_logout_redirect_without_to
    draw do
      get "account/logout" => redirect("/logout"), :as => :logout_redirect
    end

    assert_equal "/account/logout", logout_redirect_path
    get "/account/logout"
    verify_redirect "http://www.example.com/logout"
  end

  def test_namespace_redirect
    draw do
      namespace :private do
        root to: redirect("/private/index")
        get "index", to: "private#index"
      end
    end

    get "/private"
    verify_redirect "http://www.example.com/private/index"
  end

  def test_redirect_with_failing_constraint
    draw do
      get "hi", to: redirect("/foo"), constraints: ::TestRoutingMapper::GrumpyRestrictor
    end

    get "/hi"
    assert_equal 404, status
  end

  def test_redirect_with_passing_constraint
    draw do
      get "hi", to: redirect("/foo"), constraints: ->(req) { true }
    end

    get "/hi"
    assert_equal 301, status
  end

  def test_accepts_a_constraint_object_responding_to_call
    constraint = Class.new do
      def call(*); true; end
      def matches?(*); false; end
    end

    draw do
      get "/", to: "home#show", constraints: constraint.new
    end

    assert_nothing_raised do
      get "/"
    end
  end

  def test_namespace_with_controller_segment
    assert_raise(ArgumentError) do
      draw do
        namespace :admin do
          ActionDispatch.deprecator.silence do
            get "/:controller(/:action(/:id(.:format)))"
          end
        end
      end
    end
  end

  def test_namespace_without_controller_segment
    draw do
      namespace :admin do
        ActionDispatch.deprecator.silence do
          get "hello/:controllers/:action"
        end
      end
    end
    get "/admin/hello/foo/new"
    assert_equal "foo", @request.params["controllers"]
  end

  def test_session_singleton_resource
    draw do
      resource :session do
        get :create
        post :reset
      end
    end

    get "/session"
    assert_equal "sessions#create", @response.body
    assert_equal "/session", session_path

    post "/session"
    assert_equal "sessions#create", @response.body

    put "/session"
    assert_equal "sessions#update", @response.body

    delete "/session"
    assert_equal "sessions#destroy", @response.body

    get "/session/new"
    assert_equal "sessions#new", @response.body
    assert_equal "/session/new", new_session_path

    get "/session/edit"
    assert_equal "sessions#edit", @response.body
    assert_equal "/session/edit", edit_session_path

    post "/session/reset"
    assert_equal "sessions#reset", @response.body
    assert_equal "/session/reset", reset_session_path
  end

  def test_session_singleton_resource_for_api_app
    config = ActionDispatch::Routing::RouteSet::Config.new
    config.api_only = true

    self.class.stub_controllers(config) do |routes|
      routes.draw do
        resource :session do
          get :create
          post :reset
        end
      end
      @app = RoutedRackApp.new routes
    end

    get "/session"
    assert_equal "sessions#create", @response.body
    assert_equal "/session", session_path

    post "/session"
    assert_equal "sessions#create", @response.body

    put "/session"
    assert_equal "sessions#update", @response.body

    delete "/session"
    assert_equal "sessions#destroy", @response.body

    post "/session/reset"
    assert_equal "sessions#reset", @response.body
    assert_equal "/session/reset", reset_session_path

    get "/session/new"
    assert_equal "Not Found", @response.body

    get "/session/edit"
    assert_equal "Not Found", @response.body
  end

  def test_session_info_nested_singleton_resource
    draw do
      resource :session do
        resource :info
      end
    end

    get "/session/info"
    assert_equal "infos#show", @response.body
    assert_equal "/session/info", session_info_path
  end

  def test_member_on_resource
    draw do
      resource :session do
        member do
          get :crush
        end
      end
    end

    get "/session/crush"
    assert_equal "sessions#crush", @response.body
    assert_equal "/session/crush", crush_session_path
  end

  def test_redirect_modulo
    draw do
      get "account/modulo/:name", to: redirect("/%{name}s")
    end

    get "/account/modulo/name"
    verify_redirect "http://www.example.com/names"
  end

  def test_redirect_proc
    draw do
      get "account/proc/:name", to: redirect { |params, req| "/#{params[:name].pluralize}" }
    end

    get "/account/proc/person"
    verify_redirect "http://www.example.com/people"
  end

  def test_redirect_proc_with_request
    draw do
      get "account/proc_req" => redirect { |params, req| "/#{req.method}" }
    end

    get "/account/proc_req"
    verify_redirect "http://www.example.com/GET"
  end

  def test_redirect_hash_with_subdomain
    draw do
      get "mobile", to: redirect(subdomain: "mobile")
    end

    get "/mobile"
    verify_redirect "http://mobile.example.com/mobile"
  end

  def test_redirect_hash_with_domain_and_path
    draw do
      get "documentation", to: redirect(domain: "example-documentation.com", path: "")
    end

    get "/documentation"
    verify_redirect "http://www.example-documentation.com"
  end

  def test_redirect_hash_with_path
    draw do
      get "new_documentation", to: redirect(path: "/documentation/new")
    end

    get "/new_documentation"
    verify_redirect "http://www.example.com/documentation/new"
  end

  def test_redirect_hash_with_host
    draw do
      get "super_new_documentation", to: redirect(host: "super-docs.com")
    end

    get "/super_new_documentation?section=top"
    verify_redirect "http://super-docs.com/super_new_documentation?section=top"
  end

  def test_redirect_hash_path_substitution
    draw do
      get "stores/:name", to: redirect(subdomain: "stores", path: "/%{name}")
    end

    get "/stores/iernest"
    verify_redirect "http://stores.example.com/iernest"
  end

  def test_redirect_hash_path_substitution_with_catch_all
    draw do
      get "stores/:name(*rest)", to: redirect(subdomain: "stores", path: "/%{name}%{rest}")
    end

    get "/stores/iernest/products"
    verify_redirect "http://stores.example.com/iernest/products"
  end

  def test_redirect_class
    draw do
      get "youtube_favorites/:youtube_id/:name", to: redirect(YoutubeFavoritesRedirector)
    end

    get "/youtube_favorites/oHg5SJYRHA0/rick-rolld"
    verify_redirect "http://www.youtube.com/watch?v=oHg5SJYRHA0"
  end

  def test_openid
    draw do
      match "openid/login", via: [:get, :post], to: "openid#login"
    end

    get "/openid/login"
    assert_equal "openid#login", @response.body

    post "/openid/login"
    assert_equal "openid#login", @response.body
  end

  def test_websocket
    draw do
      connect "chat/live", to: "chat#live"
    end

    # HTTP/1.1 connection upgrade:
    get "/chat/live", headers: { "REQUEST_METHOD" => "GET", "HTTP_CONNECTION" => "Upgrade", "HTTP_UPGRADE" => "websocket" }
    assert_equal "chat#live", @response.body

    # `rack.protocol` connection:
    get "/chat/live", headers: { "REQUEST_METHOD" => "CONNECT", "rack.protocol" => "websocket" }
    assert_equal "chat#live", @response.body
  end

  def test_bookmarks
    draw do
      scope "bookmark", controller: "bookmarks", as: :bookmark do
        get  :new, path: "build"
        post :create, path: "create", as: ""
        put  :update
        get  :remove, action: :destroy, as: :remove
      end
    end

    get "/bookmark/build"
    assert_equal "bookmarks#new", @response.body
    assert_equal "/bookmark/build", bookmark_new_path

    post "/bookmark/create"
    assert_equal "bookmarks#create", @response.body
    assert_equal "/bookmark/create", bookmark_path

    put "/bookmark/update"
    assert_equal "bookmarks#update", @response.body
    assert_equal "/bookmark/update", bookmark_update_path

    get "/bookmark/remove"
    assert_equal "bookmarks#destroy", @response.body
    assert_equal "/bookmark/remove", bookmark_remove_path
  end

  def test_pagemarks
    draw do
      scope "pagemark", controller: "pagemarks", as: :pagemark do
        get "build", action: "new", as: "new"
        post "create", as: ""
        put  "update"
        get  "remove", action: :destroy, as: :remove
        get "", action: :show, as: :show
      end
    end

    get "/pagemark/build"
    assert_equal "pagemarks#new", @response.body
    assert_equal "/pagemark/build", pagemark_new_path

    post "/pagemark/create"
    assert_equal "pagemarks#create", @response.body
    assert_equal "/pagemark/create", pagemark_path

    put "/pagemark/update"
    assert_equal "pagemarks#update", @response.body
    assert_equal "/pagemark/update", pagemark_update_path

    get "/pagemark/remove"
    assert_equal "pagemarks#destroy", @response.body
    assert_equal "/pagemark/remove", pagemark_remove_path

    get "/pagemark"
    assert_equal "pagemarks#show", @response.body
    assert_equal "/pagemark", pagemark_show_path
  end

  def test_admin
    draw do
      constraints(ip: /192\.168\.1\.\d\d\d/) do
        get "admin" => "queenbee#index"
      end

      constraints ::TestRoutingMapper::IpRestrictor do
        get "admin/accounts" => "queenbee#accounts"
      end

      get "admin/passwords" => "queenbee#passwords", :constraints => ::TestRoutingMapper::IpRestrictor
    end

    get "/admin", headers: { "REMOTE_ADDR" => "192.168.1.100" }
    assert_equal "queenbee#index", @response.body

    get "/admin", headers: { "REMOTE_ADDR" => "10.0.0.100" }
    assert_equal "pass", @response.headers["x-cascade"]

    get "/admin/accounts", headers: { "REMOTE_ADDR" => "192.168.1.100" }
    assert_equal "queenbee#accounts", @response.body

    get "/admin/accounts", headers: { "REMOTE_ADDR" => "10.0.0.100" }
    assert_equal "pass", @response.headers["x-cascade"]

    get "/admin/passwords", headers: { "REMOTE_ADDR" => "192.168.1.100" }
    assert_equal "queenbee#passwords", @response.body

    get "/admin/passwords", headers: { "REMOTE_ADDR" => "10.0.0.100" }
    assert_equal "pass", @response.headers["x-cascade"]
  end

  def test_global
    draw do
      controller(:global) do
        get "global/hide_notice"
        get "global/export",      action: :export, as: :export_request
        get "/export/:id/:file",  action: :export, as: :export_download, constraints: { file: /.*/ }

        ActionDispatch.deprecator.silence do
          get "global/:action"
        end
      end
    end

    get "/global/dashboard"
    assert_equal "global#dashboard", @response.body

    get "/global/export"
    assert_equal "global#export", @response.body

    get "/global/hide_notice"
    assert_equal "global#hide_notice", @response.body

    get "/export/123/foo.txt"
    assert_equal "global#export", @response.body

    assert_equal "/global/export", export_request_path
    assert_equal "/global/hide_notice", global_hide_notice_path
    assert_equal "/export/123/foo.txt", export_download_path(id: 123, file: "foo.txt")
  end

  def test_local
    draw do
      ActionDispatch.deprecator.silence do
        get "/local/:action", controller: "local"
      end
    end

    get "/local/dashboard"
    assert_equal "local#dashboard", @response.body
  end

  # tests the use of dup in url_for
  def test_url_for_with_no_side_effects
    draw do
      get "/projects/status(.:format)"
    end

    # without dup, additional (and possibly unwanted) values will be present in the options (e.g. :host)
    original_options = { controller: "projects", action: "status" }
    options = original_options.dup

    url_for options

    # verify that the options passed in have not changed from the original ones
    assert_equal original_options, options
  end

  def test_url_for_does_not_modify_controller
    draw do
      get "/projects/status(.:format)"
    end

    controller = "/projects"
    options = { controller: controller, action: "status", only_path: true }
    url = url_for(options)

    assert_equal "/projects/status", url
    assert_equal "/projects", controller
  end

  # tests the arguments modification free version of define_hash_access
  def test_named_route_with_no_side_effects
    draw do
      resources :customers do
        get "profile", on: :member
      end
    end

    original_options = { host: "test.host" }
    options = original_options.dup

    profile_customer_url("customer_model", options)

    # verify that the options passed in have not changed from the original ones
    assert_equal original_options, options
  end

  def test_projects_status
    draw do
      get "/projects/status(.:format)"
    end

    assert_equal "/projects/status", url_for(controller: "projects", action: "status", only_path: true)
    assert_equal "/projects/status.json", url_for(controller: "projects", action: "status", format: "json", only_path: true)
  end

  def test_projects
    draw do
      resources :projects, controller: :project
    end

    get "/projects"
    assert_equal "project#index", @response.body
    assert_equal "/projects", projects_path

    post "/projects"
    assert_equal "project#create", @response.body

    get "/projects.xml"
    assert_equal "project#index", @response.body
    assert_equal "/projects.xml", projects_path(format: "xml")

    get "/projects/new"
    assert_equal "project#new", @response.body
    assert_equal "/projects/new", new_project_path

    get "/projects/new.xml"
    assert_equal "project#new", @response.body
    assert_equal "/projects/new.xml", new_project_path(format: "xml")

    get "/projects/1"
    assert_equal "project#show", @response.body
    assert_equal "/projects/1", project_path(id: "1")

    get "/projects/1.xml"
    assert_equal "project#show", @response.body
    assert_equal "/projects/1.xml", project_path(id: "1", format: "xml")

    get "/projects/1/edit"
    assert_equal "project#edit", @response.body
    assert_equal "/projects/1/edit", edit_project_path(id: "1")
  end

  def test_projects_for_api_app
    config = ActionDispatch::Routing::RouteSet::Config.new
    config.api_only = true

    self.class.stub_controllers(config) do |routes|
      routes.draw do
        resources :projects, controller: :project
      end
      @app = RoutedRackApp.new routes
    end

    get "/projects"
    assert_equal "project#index", @response.body
    assert_equal "/projects", projects_path

    post "/projects"
    assert_equal "project#create", @response.body

    get "/projects.xml"
    assert_equal "project#index", @response.body
    assert_equal "/projects.xml", projects_path(format: "xml")

    get "/projects/1"
    assert_equal "project#show", @response.body
    assert_equal "/projects/1", project_path(id: "1")

    get "/projects/1.xml"
    assert_equal "project#show", @response.body
    assert_equal "/projects/1.xml", project_path(id: "1", format: "xml")

    get "/projects/1/edit"
    assert_equal "Not Found", @response.body
  end

  def test_projects_with_post_action_and_new_path_on_collection
    draw do
      resources :projects, controller: :project do
        post "new", action: "new", on: :collection, as: :new
      end
    end

    post "/projects/new"
    assert_equal "project#new", @response.body
    assert_equal "/projects/new", new_projects_path
  end

  def test_projects_involvements
    draw do
      resources :projects, controller: :project do
        resources :involvements, :attachments
      end
    end

    get "/projects/1/involvements"
    assert_equal "involvements#index", @response.body
    assert_equal "/projects/1/involvements", project_involvements_path(project_id: "1")

    get "/projects/1/involvements/new"
    assert_equal "involvements#new", @response.body
    assert_equal "/projects/1/involvements/new", new_project_involvement_path(project_id: "1")

    get "/projects/1/involvements/1"
    assert_equal "involvements#show", @response.body
    assert_equal "/projects/1/involvements/1", project_involvement_path(project_id: "1", id: "1")

    put "/projects/1/involvements/1"
    assert_equal "involvements#update", @response.body

    delete "/projects/1/involvements/1"
    assert_equal "involvements#destroy", @response.body

    get "/projects/1/involvements/1/edit"
    assert_equal "involvements#edit", @response.body
    assert_equal "/projects/1/involvements/1/edit", edit_project_involvement_path(project_id: "1", id: "1")
  end

  def test_projects_attachments
    draw do
      resources :projects, controller: :project do
        resources :involvements, :attachments
      end
    end

    get "/projects/1/attachments"
    assert_equal "attachments#index", @response.body
    assert_equal "/projects/1/attachments", project_attachments_path(project_id: "1")
  end

  def test_projects_participants
    draw do
      resources :projects, controller: :project do
        resources :participants do
          put :update_all, on: :collection
        end
      end
    end

    get "/projects/1/participants"
    assert_equal "participants#index", @response.body
    assert_equal "/projects/1/participants", project_participants_path(project_id: "1")

    put "/projects/1/participants/update_all"
    assert_equal "participants#update_all", @response.body
    assert_equal "/projects/1/participants/update_all", update_all_project_participants_path(project_id: "1")
  end

  def test_projects_companies
    draw do
      resources :projects, controller: :project do
        resources :companies do
          resources :people
          resource  :avatar, controller: :avatar
        end
      end
    end

    get "/projects/1/companies"
    assert_equal "companies#index", @response.body
    assert_equal "/projects/1/companies", project_companies_path(project_id: "1")

    get "/projects/1/companies/1/people"
    assert_equal "people#index", @response.body
    assert_equal "/projects/1/companies/1/people", project_company_people_path(project_id: "1", company_id: "1")

    get "/projects/1/companies/1/avatar"
    assert_equal "avatar#show", @response.body
    assert_equal "/projects/1/companies/1/avatar", project_company_avatar_path(project_id: "1", company_id: "1")
  end

  def test_project_manager
    draw do
      resources :projects do
        resource :manager, as: :super_manager do
          post :fire
        end
      end
    end

    get "/projects/1/manager"
    assert_equal "managers#show", @response.body
    assert_equal "/projects/1/manager", project_super_manager_path(project_id: "1")

    get "/projects/1/manager/new"
    assert_equal "managers#new", @response.body
    assert_equal "/projects/1/manager/new", new_project_super_manager_path(project_id: "1")

    post "/projects/1/manager/fire"
    assert_equal "managers#fire", @response.body
    assert_equal "/projects/1/manager/fire", fire_project_super_manager_path(project_id: "1")
  end

  def test_project_images
    draw do
      resources :projects do
        resources :images, as: :funny_images do
          post :revise, on: :member
        end
      end
    end

    get "/projects/1/images"
    assert_equal "images#index", @response.body
    assert_equal "/projects/1/images", project_funny_images_path(project_id: "1")

    get "/projects/1/images/new"
    assert_equal "images#new", @response.body
    assert_equal "/projects/1/images/new", new_project_funny_image_path(project_id: "1")

    post "/projects/1/images/1/revise"
    assert_equal "images#revise", @response.body
    assert_equal "/projects/1/images/1/revise", revise_project_funny_image_path(project_id: "1", id: "1")
  end

  def test_projects_people
    draw do
      resources :projects do
        resources :people do
          nested do
            scope "/:access_token" do
              resource :avatar
            end
          end

          member do
            put  :accessible_projects
            post :resend
            post :generate_new_password
          end
        end
      end
    end

    get "/projects/1/people"
    assert_equal "people#index", @response.body
    assert_equal "/projects/1/people", project_people_path(project_id: "1")

    get "/projects/1/people/1"
    assert_equal "people#show", @response.body
    assert_equal "/projects/1/people/1", project_person_path(project_id: "1", id: "1")

    get "/projects/1/people/1/7a2dec8/avatar"
    assert_equal "avatars#show", @response.body
    assert_equal "/projects/1/people/1/7a2dec8/avatar", project_person_avatar_path(project_id: "1", person_id: "1", access_token: "7a2dec8")

    put "/projects/1/people/1/accessible_projects"
    assert_equal "people#accessible_projects", @response.body
    assert_equal "/projects/1/people/1/accessible_projects", accessible_projects_project_person_path(project_id: "1", id: "1")

    post "/projects/1/people/1/resend"
    assert_equal "people#resend", @response.body
    assert_equal "/projects/1/people/1/resend", resend_project_person_path(project_id: "1", id: "1")

    post "/projects/1/people/1/generate_new_password"
    assert_equal "people#generate_new_password", @response.body
    assert_equal "/projects/1/people/1/generate_new_password", generate_new_password_project_person_path(project_id: "1", id: "1")
  end

  def test_projects_with_resources_path_names
    draw do
      resources_path_names correlation_indexes: "info_about_correlation_indexes"

      resources :projects do
        get :correlation_indexes, on: :collection
      end
    end

    get "/projects/info_about_correlation_indexes"
    assert_equal "projects#correlation_indexes", @response.body
    assert_equal "/projects/info_about_correlation_indexes", correlation_indexes_projects_path
  end

  def test_projects_posts
    draw do
      resources :projects do
        resources :posts do
          get :archive, on: :collection
          get :toggle_view, on: :collection
          post :preview, on: :member

          resource :subscription

          resources :comments do
            post :preview, on: :collection
          end
        end
      end
    end

    get "/projects/1/posts"
    assert_equal "posts#index", @response.body
    assert_equal "/projects/1/posts", project_posts_path(project_id: "1")

    get "/projects/1/posts/archive"
    assert_equal "posts#archive", @response.body
    assert_equal "/projects/1/posts/archive", archive_project_posts_path(project_id: "1")

    get "/projects/1/posts/toggle_view"
    assert_equal "posts#toggle_view", @response.body
    assert_equal "/projects/1/posts/toggle_view", toggle_view_project_posts_path(project_id: "1")

    post "/projects/1/posts/1/preview"
    assert_equal "posts#preview", @response.body
    assert_equal "/projects/1/posts/1/preview", preview_project_post_path(project_id: "1", id: "1")

    get "/projects/1/posts/1/subscription"
    assert_equal "subscriptions#show", @response.body
    assert_equal "/projects/1/posts/1/subscription", project_post_subscription_path(project_id: "1", post_id: "1")

    get "/projects/1/posts/1/comments"
    assert_equal "comments#index", @response.body
    assert_equal "/projects/1/posts/1/comments", project_post_comments_path(project_id: "1", post_id: "1")

    post "/projects/1/posts/1/comments/preview"
    assert_equal "comments#preview", @response.body
    assert_equal "/projects/1/posts/1/comments/preview", preview_project_post_comments_path(project_id: "1", post_id: "1")
  end

  def test_replies
    draw do
      resources :replies do
        member do
          put :answer, action: :mark_as_answer
          delete :answer, action: :unmark_as_answer
        end
      end
    end

    put "/replies/1/answer"
    assert_equal "replies#mark_as_answer", @response.body

    delete "/replies/1/answer"
    assert_equal "replies#unmark_as_answer", @response.body
  end

  def test_resource_routes_with_only_and_except
    draw do
      resources :posts, only: [:index, :show] do
        resources :comments, except: :destroy
      end
    end

    get "/posts"
    assert_equal "posts#index", @response.body
    assert_equal "/posts", posts_path

    get "/posts/1"
    assert_equal "posts#show", @response.body
    assert_equal "/posts/1", post_path(id: 1)

    get "/posts/1/comments"
    assert_equal "comments#index", @response.body
    assert_equal "/posts/1/comments", post_comments_path(post_id: 1)

    post "/posts"
    assert_equal "pass", @response.headers["x-cascade"]
    put "/posts/1"
    assert_equal "pass", @response.headers["x-cascade"]
    delete "/posts/1"
    assert_equal "pass", @response.headers["x-cascade"]
    delete "/posts/1/comments"
    assert_equal "pass", @response.headers["x-cascade"]
  end

  def test_resource_routes_only_create_update_destroy
    draw do
      resource  :past, only: :destroy
      resource  :present, only: :update
      resource  :future, only: :create
    end

    delete "/past"
    assert_equal "pasts#destroy", @response.body
    assert_equal "/past", past_path

    patch "/present"
    assert_equal "presents#update", @response.body
    assert_equal "/present", present_path

    put "/present"
    assert_equal "presents#update", @response.body
    assert_equal "/present", present_path

    post "/future"
    assert_equal "futures#create", @response.body
    assert_equal "/future", future_path
  end

  def test_resources_routes_only_create_update_destroy
    draw do
      resources :relationships, only: [:create, :destroy]
      resources :friendships,   only: [:update]
    end

    post "/relationships"
    assert_equal "relationships#create", @response.body
    assert_equal "/relationships", relationships_path

    delete "/relationships/1"
    assert_equal "relationships#destroy", @response.body
    assert_equal "/relationships/1", relationship_path(1)

    patch "/friendships/1"
    assert_equal "friendships#update", @response.body
    assert_equal "/friendships/1", friendship_path(1)

    put "/friendships/1"
    assert_equal "friendships#update", @response.body
    assert_equal "/friendships/1", friendship_path(1)
  end

  def test_resource_with_slugs_in_ids
    draw do
      resources :posts
    end

    get "/posts/rails-rocks"
    assert_equal "posts#show", @response.body
    assert_equal "/posts/rails-rocks", post_path(id: "rails-rocks")
  end

  def test_resources_for_uncountable_names
    draw do
      resources :sheep do
        get "_it", on: :member
      end
    end

    assert_equal "/sheep", sheep_index_path
    assert_equal "/sheep/1", sheep_path(1)
    assert_equal "/sheep/new", new_sheep_path
    assert_equal "/sheep/1/edit", edit_sheep_path(1)
    assert_equal "/sheep/1/_it", _it_sheep_path(1)
  end

  def test_resource_does_not_modify_passed_options
    options = { id: /.+?/, format: /json|xml/ }
    draw { resource :user, **options }
    assert_equal({ id: /.+?/, format: /json|xml/ }, options)
  end

  def test_resources_does_not_modify_passed_options
    options = { id: /.+?/, format: /json|xml/ }
    draw { resources :users, **options }
    assert_equal({ id: /.+?/, format: /json|xml/ }, options)
  end

  def test_path_names
    draw do
      scope "pt", as: "pt" do
        resources :projects, path_names: { edit: "editar", new: "novo" }, path: "projetos"
        resource  :admin, path_names: { new: "novo", activate: "ativar" }, path: "administrador" do
          put :activate, on: :member
        end
      end
    end

    get "/pt/projetos"
    assert_equal "projects#index", @response.body
    assert_equal "/pt/projetos", pt_projects_path

    get "/pt/projetos/1/editar"
    assert_equal "projects#edit", @response.body
    assert_equal "/pt/projetos/1/editar", edit_pt_project_path(1)

    get "/pt/administrador"
    assert_equal "admins#show", @response.body
    assert_equal "/pt/administrador", pt_admin_path

    get "/pt/administrador/novo"
    assert_equal "admins#new", @response.body
    assert_equal "/pt/administrador/novo", new_pt_admin_path

    put "/pt/administrador/ativar"
    assert_equal "admins#activate", @response.body
    assert_equal "/pt/administrador/ativar", activate_pt_admin_path
  end

  def test_path_option_override
    draw do
      scope "pt", as: "pt" do
        resources :projects, path_names: { new: "novo" }, path: "projetos" do
          put :close, on: :member, path: "fechar"
          get :open, on: :new, path: "abrir"
        end
      end
    end

    get "/pt/projetos/novo/abrir"
    assert_equal "projects#open", @response.body
    assert_equal "/pt/projetos/novo/abrir", open_new_pt_project_path

    put "/pt/projetos/1/fechar"
    assert_equal "projects#close", @response.body
    assert_equal "/pt/projetos/1/fechar", close_pt_project_path(1)
  end

  def test_sprockets
    draw do
      get "sprockets.js" => ::TestRoutingMapper::SprocketsApp
    end

    get "/sprockets.js"
    assert_equal "javascripts", @response.body
  end

  def test_update_person_route
    draw do
      get "people/:id/update", to: "people#update", as: :update_person
    end

    get "/people/1/update"
    assert_equal "people#update", @response.body

    assert_equal "/people/1/update", update_person_path(id: 1)
  end

  def test_update_project_person
    draw do
      get "/projects/:project_id/people/:id/update", to: "people#update", as: :update_project_person
    end

    get "/projects/1/people/2/update"
    assert_equal "people#update", @response.body

    assert_equal "/projects/1/people/2/update", update_project_person_path(project_id: 1, id: 2)
  end

  def test_forum_products
    draw do
      namespace :forum do
        resources :products, path: "" do
          resources :questions
        end
      end
    end

    get "/forum"
    assert_equal "forum/products#index", @response.body
    assert_equal "/forum", forum_products_path

    get "/forum/basecamp"
    assert_equal "forum/products#show", @response.body
    assert_equal "/forum/basecamp", forum_product_path(id: "basecamp")

    get "/forum/basecamp/questions"
    assert_equal "forum/questions#index", @response.body
    assert_equal "/forum/basecamp/questions", forum_product_questions_path(product_id: "basecamp")

    get "/forum/basecamp/questions/1"
    assert_equal "forum/questions#show", @response.body
    assert_equal "/forum/basecamp/questions/1", forum_product_question_path(product_id: "basecamp", id: 1)
  end

  def test_articles_perma
    draw do
      get "articles/:year/:month/:day/:title", to: "articles#show", as: :article
    end

    get "/articles/2009/08/18/rails-3"
    assert_equal "articles#show", @response.body

    assert_equal "/articles/2009/8/18/rails-3", article_path(year: 2009, month: 8, day: 18, title: "rails-3")
  end

  def test_account_namespace
    draw do
      namespace :account do
        resource :subscription, :credit, :credit_card
      end
    end

    get "/account/subscription"
    assert_equal "account/subscriptions#show", @response.body
    assert_equal "/account/subscription", account_subscription_path

    get "/account/credit"
    assert_equal "account/credits#show", @response.body
    assert_equal "/account/credit", account_credit_path

    get "/account/credit_card"
    assert_equal "account/credit_cards#show", @response.body
    assert_equal "/account/credit_card", account_credit_card_path
  end

  def test_nested_namespace
    draw do
      namespace :account do
        namespace :admin do
          resource :subscription
        end
      end
    end

    get "/account/admin/subscription"
    assert_equal "account/admin/subscriptions#show", @response.body
    assert_equal "/account/admin/subscription", account_admin_subscription_path
  end

  def test_namespace_nested_in_resources
    draw do
      resources :clients do
        namespace :google do
          resource :account do
            namespace :secret do
              resource :info
            end
          end
        end
      end
    end

    get "/clients/1/google/account"
    assert_equal "/clients/1/google/account", client_google_account_path(1)
    assert_equal "google/accounts#show", @response.body

    get "/clients/1/google/account/secret/info"
    assert_equal "/clients/1/google/account/secret/info", client_google_account_secret_info_path(1)
    assert_equal "google/secret/infos#show", @response.body
  end

  def test_namespace_with_options
    draw do
      namespace :users, path: "usuarios" do
        root to: "home#index"
      end
    end

    get "/usuarios"
    assert_equal "/usuarios", users_root_path
    assert_equal "users/home#index", @response.body
  end

  def test_only_option_should_override_scope
    draw do
      scope only: :show do
        namespace :only do
          resources :sectors, only: :index
        end
      end
    end

    get "/only/sectors"
    assert_equal "only/sectors#index", @response.body
    assert_equal "/only/sectors", only_sectors_path

    get "/only/sectors/1"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { only_sector_path(id: "1") }
  end

  def test_only_option_should_not_inherit
    draw do
      scope only: :show do
        namespace :only do
          resources :sectors, only: :index do
            resources :companies
            resource  :leader
          end
        end
      end
    end

    get "/only/sectors/1/companies/2"
    assert_equal "only/companies#show", @response.body
    assert_equal "/only/sectors/1/companies/2", only_sector_company_path(sector_id: "1", id: "2")

    get "/only/sectors/1/leader"
    assert_equal "only/leaders#show", @response.body
    assert_equal "/only/sectors/1/leader", only_sector_leader_path(sector_id: "1")
  end

  def test_except_option_should_override_scope
    draw do
      scope except: :index do
        namespace :except do
          resources :sectors, except: [:show, :update, :destroy]
        end
      end
    end

    get "/except/sectors"
    assert_equal "except/sectors#index", @response.body
    assert_equal "/except/sectors", except_sectors_path

    get "/except/sectors/1"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { except_sector_path(id: "1") }
  end

  def test_except_option_should_not_inherit
    draw do
      scope except: :index do
        namespace :except do
          resources :sectors, except: [:show, :update, :destroy] do
            resources :companies
            resource  :leader
          end
        end
      end
    end

    get "/except/sectors/1/companies/2"
    assert_equal "except/companies#show", @response.body
    assert_equal "/except/sectors/1/companies/2", except_sector_company_path(sector_id: "1", id: "2")

    get "/except/sectors/1/leader"
    assert_equal "except/leaders#show", @response.body
    assert_equal "/except/sectors/1/leader", except_sector_leader_path(sector_id: "1")
  end

  def test_except_option_should_override_scoped_only
    draw do
      scope only: :show do
        namespace :only do
          resources :sectors, only: :index do
            resources :managers, except: [:show, :update, :destroy]
          end
        end
      end
    end

    get "/only/sectors/1/managers"
    assert_equal "only/managers#index", @response.body
    assert_equal "/only/sectors/1/managers", only_sector_managers_path(sector_id: "1")

    get "/only/sectors/1/managers/2"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { only_sector_manager_path(sector_id: "1", id: "2") }
  end

  def test_only_option_should_override_scoped_except
    draw do
      scope except: :index do
        namespace :except do
          resources :sectors, except: [:show, :update, :destroy] do
            resources :managers, only: :index
          end
        end
      end
    end

    get "/except/sectors/1/managers"
    assert_equal "except/managers#index", @response.body
    assert_equal "/except/sectors/1/managers", except_sector_managers_path(sector_id: "1")

    get "/except/sectors/1/managers/2"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { except_sector_manager_path(sector_id: "1", id: "2") }
  end

  def test_only_scope_should_override_parent_scope
    draw do
      scope only: :show do
        namespace :only do
          resources :sectors, only: :index do
            resources :companies do
              scope only: :index do
                resources :divisions
              end
            end
          end
        end
      end
    end

    get "/only/sectors/1/companies/2/divisions"
    assert_equal "only/divisions#index", @response.body
    assert_equal "/only/sectors/1/companies/2/divisions", only_sector_company_divisions_path(sector_id: "1", company_id: "2")

    get "/only/sectors/1/companies/2/divisions/3"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { only_sector_company_division_path(sector_id: "1", company_id: "2", id: "3") }
  end

  def test_except_scope_should_override_parent_scope
    draw do
      scope except: :index do
        namespace :except do
          resources :sectors, except: [:show, :update, :destroy] do
            resources :companies do
              scope except: [:show, :update, :destroy] do
                resources :divisions
              end
            end
          end
        end
      end
    end

    get "/except/sectors/1/companies/2/divisions"
    assert_equal "except/divisions#index", @response.body
    assert_equal "/except/sectors/1/companies/2/divisions", except_sector_company_divisions_path(sector_id: "1", company_id: "2")

    get "/except/sectors/1/companies/2/divisions/3"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { except_sector_company_division_path(sector_id: "1", company_id: "2", id: "3") }
  end

  def test_except_scope_should_override_parent_only_scope
    draw do
      scope only: :show do
        namespace :only do
          resources :sectors, only: :index do
            resources :companies do
              scope except: [:show, :update, :destroy] do
                resources :departments
              end
            end
          end
        end
      end
    end

    get "/only/sectors/1/companies/2/departments"
    assert_equal "only/departments#index", @response.body
    assert_equal "/only/sectors/1/companies/2/departments", only_sector_company_departments_path(sector_id: "1", company_id: "2")

    get "/only/sectors/1/companies/2/departments/3"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { only_sector_company_department_path(sector_id: "1", company_id: "2", id: "3") }
  end

  def test_only_scope_should_override_parent_except_scope
    draw do
      scope except: :index do
        namespace :except do
          resources :sectors, except: [:show, :update, :destroy] do
            resources :companies do
              scope only: :index do
                resources :departments
              end
            end
          end
        end
      end
    end

    get "/except/sectors/1/companies/2/departments"
    assert_equal "except/departments#index", @response.body
    assert_equal "/except/sectors/1/companies/2/departments", except_sector_company_departments_path(sector_id: "1", company_id: "2")

    get "/except/sectors/1/companies/2/departments/3"
    assert_equal "Not Found", @response.body
    assert_raise(NoMethodError) { except_sector_company_department_path(sector_id: "1", company_id: "2", id: "3") }
  end

  def test_resources_are_not_pluralized
    draw do
      namespace :transport do
        resources :taxis
      end
    end

    get "/transport/taxis"
    assert_equal "transport/taxis#index", @response.body
    assert_equal "/transport/taxis", transport_taxis_path

    get "/transport/taxis/new"
    assert_equal "transport/taxis#new", @response.body
    assert_equal "/transport/taxis/new", new_transport_taxi_path

    post "/transport/taxis"
    assert_equal "transport/taxis#create", @response.body

    get "/transport/taxis/1"
    assert_equal "transport/taxis#show", @response.body
    assert_equal "/transport/taxis/1", transport_taxi_path(id: "1")

    get "/transport/taxis/1/edit"
    assert_equal "transport/taxis#edit", @response.body
    assert_equal "/transport/taxis/1/edit", edit_transport_taxi_path(id: "1")

    put "/transport/taxis/1"
    assert_equal "transport/taxis#update", @response.body

    delete "/transport/taxis/1"
    assert_equal "transport/taxis#destroy", @response.body
  end

  def test_singleton_resources_are_not_singularized
    draw do
      namespace :medical do
        resource :taxis
      end
    end

    get "/medical/taxis/new"
    assert_equal "medical/taxis#new", @response.body
    assert_equal "/medical/taxis/new", new_medical_taxis_path

    post "/medical/taxis"
    assert_equal "medical/taxis#create", @response.body

    get "/medical/taxis"
    assert_equal "medical/taxis#show", @response.body
    assert_equal "/medical/taxis", medical_taxis_path

    get "/medical/taxis/edit"
    assert_equal "medical/taxis#edit", @response.body
    assert_equal "/medical/taxis/edit", edit_medical_taxis_path

    put "/medical/taxis"
    assert_equal "medical/taxis#update", @response.body

    delete "/medical/taxis"
    assert_equal "medical/taxis#destroy", @response.body
  end

  def test_greedy_resource_id_regexp_doesnt_match_edit_and_custom_action
    draw do
      resources :sections, id: /.+/ do
        get :preview, on: :member
      end
    end

    get "/sections/1/edit"
    assert_equal "sections#edit", @response.body
    assert_equal "/sections/1/edit", edit_section_path(id: "1")

    get "/sections/1/preview"
    assert_equal "sections#preview", @response.body
    assert_equal "/sections/1/preview", preview_section_path(id: "1")
  end

  def test_resource_constraints_are_pushed_to_scope
    draw do
      namespace :wiki do
        resources :articles, id: /[^\/]+/ do
          resources :comments, only: [:create, :new]
        end
      end
    end

    get "/wiki/articles/Ruby_on_Rails_3.0"
    assert_equal "wiki/articles#show", @response.body
    assert_equal "/wiki/articles/Ruby_on_Rails_3.0", wiki_article_path(id: "Ruby_on_Rails_3.0")

    get "/wiki/articles/Ruby_on_Rails_3.0/comments/new"
    assert_equal "wiki/comments#new", @response.body
    assert_equal "/wiki/articles/Ruby_on_Rails_3.0/comments/new", new_wiki_article_comment_path(article_id: "Ruby_on_Rails_3.0")

    post "/wiki/articles/Ruby_on_Rails_3.0/comments"
    assert_equal "wiki/comments#create", @response.body
    assert_equal "/wiki/articles/Ruby_on_Rails_3.0/comments", wiki_article_comments_path(article_id: "Ruby_on_Rails_3.0")
  end

  def test_resources_path_can_be_a_symbol
    draw do
      resources :wiki_pages, path: :pages
      resource :wiki_account, path: :my_account
    end

    get "/pages"
    assert_equal "wiki_pages#index", @response.body
    assert_equal "/pages", wiki_pages_path

    get "/pages/Ruby_on_Rails"
    assert_equal "wiki_pages#show", @response.body
    assert_equal "/pages/Ruby_on_Rails", wiki_page_path(id: "Ruby_on_Rails")

    get "/my_account"
    assert_equal "wiki_accounts#show", @response.body
    assert_equal "/my_account", wiki_account_path
  end

  def test_redirect_https
    draw do
      get "secure", to: redirect("/secure/login")
    end

    with_https do
      get "/secure"
      verify_redirect "https://www.example.com/secure/login"
    end
  end

  def test_path_parameters_is_not_stale
    draw do
      scope "/countries/:country", constraints: lambda { |params, req| %w(all France).include?(params[:country]) } do
        get "/",       to: "countries#index"
        get "/cities", to: "countries#cities"
      end

      get "/countries/:country/(*other)", to: redirect { |params, req| params[:other] ? "/countries/all/#{params[:other]}" : "/countries/all" }
    end

    get "/countries/France"
    assert_equal "countries#index", @response.body

    get "/countries/France/cities"
    assert_equal "countries#cities", @response.body

    get "/countries/UK"
    verify_redirect "http://www.example.com/countries/all"

    get "/countries/UK/cities"
    verify_redirect "http://www.example.com/countries/all/cities"
  end

  def test_constraints_block_not_carried_to_following_routes
    draw do
      scope "/italians" do
        get "/writers", to: "italians#writers", constraints: ::TestRoutingMapper::IpRestrictor
        get "/sculptors", to: "italians#sculptors"
        get "/painters/:painter", to: "italians#painters", constraints: { painter: /michelangelo/ }
      end
    end

    get "/italians/writers"
    assert_equal "Not Found", @response.body

    get "/italians/sculptors"
    assert_equal "italians#sculptors", @response.body

    get "/italians/painters/botticelli"
    assert_equal "Not Found", @response.body

    get "/italians/painters/michelangelo"
    assert_equal "italians#painters", @response.body
  end

  def test_custom_resource_actions_defined_using_string
    draw do
      resources :customers do
        resources :invoices do
          get "aged/:months", on: :collection, action: :aged, as: :aged
        end

        get "inactive", on: :collection
        post "deactivate", on: :member
        get "old", on: :collection, as: :stale
      end
    end

    get "/customers/inactive"
    assert_equal "customers#inactive", @response.body
    assert_equal "/customers/inactive", inactive_customers_path

    post "/customers/1/deactivate"
    assert_equal "customers#deactivate", @response.body
    assert_equal "/customers/1/deactivate", deactivate_customer_path(id: "1")

    get "/customers/old"
    assert_equal "customers#old", @response.body
    assert_equal "/customers/old", stale_customers_path

    get "/customers/1/invoices/aged/3"
    assert_equal "invoices#aged", @response.body
    assert_equal "/customers/1/invoices/aged/3", aged_customer_invoices_path(customer_id: "1", months: "3")
  end

  def test_route_defined_in_resources_scope_level
    draw do
      resources :customers do
        get "export"
      end
    end

    get "/customers/1/export"
    assert_equal "customers#export", @response.body
    assert_equal "/customers/1/export", customer_export_path(customer_id: "1")
  end

  def test_named_character_classes_in_regexp_constraints
    draw do
      get "/purchases/:token/:filename",
        to: "purchases#fetch",
        token: /[[:alnum:]]{10}/,
        filename: /(.+)/,
        as: :purchase
    end

    get "/purchases/315004be7e/Ruby_on_Rails_3.pdf"
    assert_equal "purchases#fetch", @response.body
    assert_equal "/purchases/315004be7e/Ruby_on_Rails_3.pdf", purchase_path(token: "315004be7e", filename: "Ruby_on_Rails_3.pdf")
  end

  def test_nested_resource_constraints
    draw do
      resources :lists, id: /([A-Za-z0-9]{25})|default/ do
        resources :todos, id: /\d+/
      end
    end

    get "/lists/01234012340123401234fffff"
    assert_equal "lists#show", @response.body
    assert_equal "/lists/01234012340123401234fffff", list_path(id: "01234012340123401234fffff")

    get "/lists/01234012340123401234fffff/todos/1"
    assert_equal "todos#show", @response.body
    assert_equal "/lists/01234012340123401234fffff/todos/1", list_todo_path(list_id: "01234012340123401234fffff", id: "1")

    get "/lists/2/todos/1"
    assert_equal "Not Found", @response.body
    assert_raises(ActionController::UrlGenerationError) { list_todo_path(list_id: "2", id: "1") }
  end

  def test_redirect_argument_error
    routes = Class.new { include ActionDispatch::Routing::Redirection }.new
    assert_raises(ArgumentError) { routes.redirect Object.new }
  end

  def test_named_route_check
    before, after = nil

    draw do
      before = has_named_route?(:hello)
      get "/hello", as: :hello, to: "hello#world"
      after = has_named_route?(:hello)
    end

    assert_not before, "expected to not have named route :hello before route definition"
    assert after, "expected to have named route :hello after route definition"
  end

  def test_explicitly_avoiding_the_named_route
    draw do
      scope as: "routes" do
        get "/c/:id", as: :collision, to: "collision#show"
        get "/collision", to: "collision#show"
        get "/no_collision", to: "collision#show", as: nil
      end
    end

    assert_not respond_to?(:routes_no_collision_path)
  end

  def test_controller_name_with_leading_slash_raise_error
    assert_raise(ArgumentError) do
      draw { get "/feeds/:service", to: "/feeds#show" }
    end

    assert_raise(ArgumentError) do
      draw { get "/feeds/:service", controller: "/feeds", action: "show" }
    end

    assert_raise(ArgumentError) do
      draw { get "/api/feeds/:service", to: "/api/feeds#show" }
    end

    assert_raise(ArgumentError) do
      draw { resources :feeds, controller: "/feeds" }
    end
  end

  def test_invalid_route_name_raises_error
    assert_raise(ArgumentError) do
      draw { get "/products", to: "products#index", as: "products " }
    end

    assert_raise(ArgumentError) do
      draw { get "/products", to: "products#index", as: " products" }
    end

    assert_raise(ArgumentError) do
      draw { get "/products", to: "products#index", as: "products!" }
    end

    assert_raise(ArgumentError) do
      draw { get "/products", to: "products#index", as: "products index" }
    end

    assert_raise(ArgumentError) do
      draw { get "/products", to: "products#index", as: "1products" }
    end
  end

  def test_duplicate_route_name_raises_error
    assert_raise(ArgumentError) do
      draw do
        get "/collision", to: "collision#show", as: "collision"
        get "/duplicate", to: "duplicate#show", as: "collision"
      end
    end
  end

  def test_duplicate_route_name_via_resources_raises_error
    assert_raise(ArgumentError) do
      draw do
        resources :collisions
        get "/collision", to: "collision#show", as: "collision"
      end
    end
  end

  def test_nested_route_in_nested_resource
    draw do
      resources :posts, only: [:index, :show] do
        resources :comments, except: :destroy do
          get "views" => "comments#views", :as => :views
        end
      end
    end

    get "/posts/1/comments/2/views"
    assert_equal "comments#views", @response.body
    assert_equal "/posts/1/comments/2/views", post_comment_views_path(post_id: "1", comment_id: "2")
  end

  def test_root_in_deeply_nested_scope
    draw do
      resources :posts, only: [:index, :show] do
        namespace :admin do
          root to: "index#index"
        end
      end
    end

    get "/posts/1/admin"
    assert_equal "admin/index#index", @response.body
    assert_equal "/posts/1/admin", post_admin_root_path(post_id: "1")
  end

  def test_custom_param
    draw do
      resources :profiles, param: :username do
        get :details, on: :member
        resources :messages
      end
    end

    get "/profiles/bob"
    assert_equal "profiles#show", @response.body
    assert_equal "bob", @request.params[:username]

    get "/profiles/bob/details"
    assert_equal "bob", @request.params[:username]

    get "/profiles/bob/messages/34"
    assert_equal "bob", @request.params[:profile_username]
    assert_equal "34", @request.params[:id]
  end

  def test_custom_param_constraint
    draw do
      resources :profiles, param: :username, username: /[a-z]+/ do
        get :details, on: :member
        resources :messages
      end
    end

    get "/profiles/bob1"
    assert_equal 404, @response.status

    get "/profiles/bob1/details"
    assert_equal 404, @response.status

    get "/profiles/bob1/messages/34"
    assert_equal 404, @response.status
  end

  def test_shallow_custom_param
    draw do
      resources :orders do
        constraints download: /[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}/ do
          resources :downloads, param: :download, shallow: true
        end
      end
    end

    get "/downloads/0c0c0b68-d24b-11e1-a861-001ff3fffe6f.zip"
    assert_equal "downloads#show", @response.body
    assert_equal "0c0c0b68-d24b-11e1-a861-001ff3fffe6f", @request.params[:download]
  end

  def test_colon_containing_custom_param
    ex = assert_raises(ArgumentError) {
      draw do
        resources :profiles, param: "username/:is_admin"
      end
    }

    assert_match(/:param option can't contain colon/, ex.message)
  end

  def test_action_from_path_is_frozen
    draw do
      get "search" => "search"
    end

    get "/search"
    assert_predicate @request.params[:action], :frozen?
  end

  def test_multiple_positional_args_with_the_same_name
    draw do
      get "/downloads/:id/:id.tar" => "downloads#show", as: :download, format: false
    end

    expected_params = {
      controller: "downloads",
      action:     "show",
      id:         "1"
    }

    get "/downloads/1/1.tar"
    assert_equal "downloads#show", @response.body
    assert_equal expected_params, @request.path_parameters
    assert_equal "/downloads/1/1.tar", download_path("1")
    assert_equal "/downloads/1/1.tar", download_path("1", "1")
  end

  def test_absolute_controller_namespace
    draw do
      namespace :foo do
        get "/", to: "/bar#index", as: "root"
      end
    end

    get "/foo"
    assert_equal "bar#index", @response.body
    assert_equal "/foo", foo_root_path
  end

  def test_namespace_as_controller
    draw do
      namespace :foo do
        get "/", to: "/bar#index", as: "root"
      end
    end

    get "/foo"
    assert_equal "bar#index", @response.body
    assert_equal "/foo", foo_root_path
  end

  def test_trailing_slash
    draw do
      resources :streams
    end

    get "/streams"
    assert_predicate @response, :ok?, "route without trailing slash should work"

    get "/streams/"
    assert_predicate @response, :ok?, "route with trailing slash should work"

    get "/streams?foobar"
    assert_predicate @response, :ok?, "route without trailing slash and with QUERY_STRING should work"

    get "/streams/?foobar"
    assert_predicate @response, :ok?, "route with trailing slash and with QUERY_STRING should work"
  end

  def test_route_with_dashes_in_path
    draw do
      get "/contact-us", to: "pages#contact_us"
    end

    get "/contact-us"
    assert_equal "pages#contact_us", @response.body
    assert_equal "/contact-us", contact_us_path
  end

  def test_shorthand_route_with_dashes_in_path
    draw do
      get "/about-us/index"
    end

    get "/about-us/index"
    assert_equal "about_us#index", @response.body
    assert_equal "/about-us/index", about_us_index_path
  end

  def test_resource_routes_with_dashes_in_path
    draw do
      resources :photos, only: [:show] do
        get "user-favorites", on: :collection
        get "preview-photo", on: :member
        get "summary-text"
      end
    end

    get "/photos/user-favorites"
    assert_equal "photos#user_favorites", @response.body
    assert_equal "/photos/user-favorites", user_favorites_photos_path

    get "/photos/1/preview-photo"
    assert_equal "photos#preview_photo", @response.body
    assert_equal "/photos/1/preview-photo", preview_photo_photo_path("1")

    get "/photos/1/summary-text"
    assert_equal "photos#summary_text", @response.body
    assert_equal "/photos/1/summary-text", photo_summary_text_path("1")

    get "/photos/1"
    assert_equal "photos#show", @response.body
    assert_equal "/photos/1", photo_path("1")
  end

  def test_shallow_path_inside_namespace_is_not_added_twice
    draw do
      namespace :admin do
        shallow do
          resources :posts do
            resources :comments
          end
        end
      end
    end

    get "/admin/posts/1/comments"
    assert_equal "admin/comments#index", @response.body
    assert_equal "/admin/posts/1/comments", admin_post_comments_path("1")
  end

  def test_mix_string_to_controller_action
    draw do
      get "/projects", controller: "project_files",
                       action: "index",
                       to: "comments#index"
    end
    get "/projects"
    assert_equal "comments#index", @response.body
  end

  def test_mix_string_to_controller
    draw do
      get "/projects", controller: "project_files",
                       to: "comments#index"
    end
    get "/projects"
    assert_equal "comments#index", @response.body
  end

  def test_mix_string_to_action
    draw do
      get "/projects", action: "index",
                       to: "comments#index"
    end
    get "/projects"
    assert_equal "comments#index", @response.body
  end

  def test_shallow_path_and_prefix_are_not_added_to_non_shallow_routes
    draw do
      scope shallow_path: "projects", shallow_prefix: "project" do
        resources :projects do
          resources :files, controller: "project_files", shallow: true
        end
      end
    end

    get "/projects"
    assert_equal "projects#index", @response.body
    assert_equal "/projects", projects_path

    get "/projects/new"
    assert_equal "projects#new", @response.body
    assert_equal "/projects/new", new_project_path

    post "/projects"
    assert_equal "projects#create", @response.body

    get "/projects/1"
    assert_equal "projects#show", @response.body
    assert_equal "/projects/1", project_path("1")

    get "/projects/1/edit"
    assert_equal "projects#edit", @response.body
    assert_equal "/projects/1/edit", edit_project_path("1")

    patch "/projects/1"
    assert_equal "projects#update", @response.body

    delete "/projects/1"
    assert_equal "projects#destroy", @response.body

    get "/projects/1/files"
    assert_equal "project_files#index", @response.body
    assert_equal "/projects/1/files", project_files_path("1")

    get "/projects/1/files/new"
    assert_equal "project_files#new", @response.body
    assert_equal "/projects/1/files/new", new_project_file_path("1")

    post "/projects/1/files"
    assert_equal "project_files#create", @response.body

    get "/projects/files/2"
    assert_equal "project_files#show", @response.body
    assert_equal "/projects/files/2", project_file_path("2")

    get "/projects/files/2/edit"
    assert_equal "project_files#edit", @response.body
    assert_equal "/projects/files/2/edit", edit_project_file_path("2")

    patch "/projects/files/2"
    assert_equal "project_files#update", @response.body

    delete "/projects/files/2"
    assert_equal "project_files#destroy", @response.body
  end

  def test_scope_path_is_copied_to_shallow_path
    draw do
      scope path: "foo" do
        resources :posts do
          resources :comments, shallow: true
        end
      end
    end

    assert_equal "/foo/comments/1", comment_path("1")
  end

  def test_scope_as_is_copied_to_shallow_prefix
    draw do
      scope as: "foo" do
        resources :posts do
          resources :comments, shallow: true
        end
      end
    end

    assert_equal "/comments/1", foo_comment_path("1")
  end

  def test_scope_shallow_prefix_is_not_overwritten_by_as
    draw do
      scope as: "foo", shallow_prefix: "bar" do
        resources :posts do
          resources :comments, shallow: true
        end
      end
    end

    assert_equal "/comments/1", bar_comment_path("1")
  end

  def test_scope_shallow_path_is_not_overwritten_by_path
    draw do
      scope path: "foo", shallow_path: "bar" do
        resources :posts do
          resources :comments, shallow: true
        end
      end
    end

    assert_equal "/bar/comments/1", comment_path("1")
  end

  def test_resource_where_as_is_empty
    draw do
      resource :post, as: ""

      scope "post", as: "post" do
        resource :comment, as: ""
      end
    end

    assert_equal "/post/new", new_path
    assert_equal "/post/comment/new", new_post_path
  end

  def test_resources_where_as_is_empty
    draw do
      resources :posts, as: ""

      scope "posts", as: "posts" do
        resources :comments, as: ""
      end
    end

    assert_equal "/posts/new", new_path
    assert_equal "/posts/comments/new", new_posts_path
  end

  def test_scope_where_as_is_empty
    draw do
      scope "post", as: "" do
        resource :user
        resources :comments
      end
    end

    assert_equal "/post/user/new", new_user_path
    assert_equal "/post/comments/new", new_comment_path
  end

  def test_head_fetch_with_mount_on_root
    draw do
      get "/home" => "test#index"
      mount lambda { |env| [200, {}, [env["REQUEST_METHOD"]]] }, at: "/"
    end

    # HEAD request should match `get /home` rather than the
    # lower-precedence Rack app mounted at `/`.
    head "/home"
    assert_response :ok
    assert_equal "test#index", @response.body

    # But the Rack app can still respond to its own HEAD requests.
    head "/foobar"
    assert_response :ok
    assert_equal "HEAD", @response.body
  end

  def test_passing_action_parameters_to_url_helpers_raises_error_if_parameters_are_not_permitted
    draw do
      root to: "projects#index"
    end
    params = ActionController::Parameters.new(id: "1")

    assert_raises ActionController::UnfilteredParameters do
      root_path(params)
    end
  end

  def test_passing_action_parameters_to_url_helpers_is_allowed_if_parameters_are_permitted
    draw do
      root to: "projects#index"
    end
    params = ActionController::Parameters.new(id: "1")
    params.permit!

    assert_equal "/?id=1", root_path(params)
  end

  def test_dynamic_controller_segments_are_deprecated
    assert_deprecated(ActionDispatch.deprecator) do
      draw do
        get "/:controller", action: "index"
      end
    end
  end

  def test_dynamic_action_segments_are_deprecated
    assert_deprecated(ActionDispatch.deprecator) do
      draw do
        get "/pages/:action", controller: "pages"
      end
    end
  end

  def test_multiple_roots_raises_error
    ex = assert_raises(ArgumentError) {
      draw do
        root "pages#index", constraints: { host: "www.example.com" }
        root "admin/pages#index", constraints: { host: "admin.example.com" }
      end
    }
    assert_match(/Invalid route name, already in use: 'root'/, ex.message)
  end

  def test_multiple_named_roots
    draw do
      namespace :foo do
        root "pages#index", constraints: { host: "www.example.com" }
        root "admin/pages#index", constraints: { host: "admin.example.com" }, as: :admin_root
      end

      root "pages#index", constraints: { host: "www.example.com" }
      root "admin/pages#index", constraints: { host: "admin.example.com" },  as: :admin_root
    end

    get "http://www.example.com/foo"
    assert_equal "foo/pages#index", @response.body

    get "http://admin.example.com/foo"
    assert_equal "foo/admin/pages#index", @response.body

    get "http://www.example.com/"
    assert_equal "pages#index", @response.body

    get "http://admin.example.com/"
    assert_equal "admin/pages#index", @response.body
  end

  def test_multiple_namespaced_roots
    draw do
      namespace :foo do
        root "test#index"
      end

      root "test#index"

      namespace :bar do
        root "test#index"
      end
    end

    assert_equal "/foo", foo_root_path
    assert_equal "/", root_path
    assert_equal "/bar", bar_root_path
  end

  def test_nested_routes_under_format_resource
    draw do
      resources :formats do
        resources :items
      end
    end

    get "/formats/1/items.json"
    assert_equal 200, @response.status
    assert_equal "items#index", @response.body
    assert_equal "/formats/1/items.json", format_items_path(1, :json)

    get "/formats/1/items/2.json"
    assert_equal 200, @response.status
    assert_equal "items#show", @response.body
    assert_equal "/formats/1/items/2.json", format_item_path(1, 2, :json)
  end

  def test_routes_with_double_colon
    draw do
      get "/sort::sort", to: "sessions#sort"
    end

    get "/sort:asc"
    assert_equal "asc", @request.params[:sort]
    assert_equal "sessions#sort", @response.body
  end

private
  def draw(&block)
    self.class.stub_controllers do |routes|
      routes.default_url_options = { host: "www.example.com" }
      routes.draw(&block)
      @app = RoutedRackApp.new routes
    end
  end

  def url_for(options = {})
    @app.routes.url_helpers.url_for(options)
  end

  def method_missing(method, ...)
    if method.match?(/_(path|url)$/)
      @app.routes.url_helpers.send(method, ...)
    else
      super
    end
  end

  def with_https
    old_https = https?
    https!
    yield
  ensure
    https!(old_https)
  end

  def verify_redirect(url, status = 301)
    assert_equal status, @response.status
    assert_equal url, @response.headers["Location"]
    assert_equal "", @response.body
  end
end

class TestAltApp < ActionDispatch::IntegrationTest
  class AltRequest < ActionDispatch::Request
    attr_accessor :path_parameters, :path_info, :script_name
    attr_reader :env

    def initialize(env)
      @path_parameters = {}
      @env = env
      @path_info = "/"
      @script_name = ""
      super
    end

    def request_method
      "GET"
    end

    def ip
      "127.0.0.1"
    end

    def x_header
      @env["HTTP_X_HEADER"] || ""
    end
  end

  class XHeader
    def call(env)
      [200, { "Content-Type" => "text/html" }, ["XHeader"]]
    end
  end

  class AltApp
    def call(env)
      [200, { "Content-Type" => "text/html" }, ["Alternative App"]]
    end
  end

  AltRoutes = Class.new(ActionDispatch::Routing::RouteSet) {
    def request_class
      AltRequest
    end
  }.new
  AltRoutes.draw do
    get "/" => TestAltApp::XHeader.new, :constraints => { x_header: /HEADER/ }
    get "/" => TestAltApp::AltApp.new
  end

  APP = build_app AltRoutes

  def app
    APP
  end

  def test_alt_request_without_header
    get "/"
    assert_equal "Alternative App", @response.body
  end

  def test_alt_request_with_matched_header
    get "/", headers: { "HTTP_X_HEADER" => "HEADER" }
    assert_equal "XHeader", @response.body
  end

  def test_alt_request_with_unmatched_header
    get "/", headers: { "HTTP_X_HEADER" => "NON_MATCH" }
    assert_equal "Alternative App", @response.body
  end
end

class TestAppendingRoutes < ActionDispatch::IntegrationTest
  def simple_app(resp)
    lambda { |e| [ 200, { "Content-Type" => "text/plain" }, [resp] ] }
  end

  def setup
    super
    s = self
    routes = ActionDispatch::Routing::RouteSet.new
    routes.append do
      get "/hello"   => s.simple_app("fail")
      get "/goodbye" => s.simple_app("goodbye")
    end

    routes.draw do
      get "/hello" => s.simple_app("hello")
    end
    @app = self.class.build_app routes
  end

  def test_goodbye_should_be_available
    get "/goodbye"
    assert_equal "goodbye", @response.body
  end

  def test_hello_should_not_be_overwritten
    get "/hello"
    assert_equal "hello", @response.body
  end

  def test_missing_routes_are_still_missing
    get "/random"
    assert_equal 404, @response.status
  end
end

class TestNamespaceWithControllerOption < ActionDispatch::IntegrationTest
  module ::Admin
    class StorageFilesController < ActionController::Base
      def index
        render plain: "admin/storage_files#index"
      end
    end
  end

  def draw(&block)
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw(&block)
    @app = self.class.build_app routes
    @routes = routes
  end

  def test_missing_controller
    ex = assert_raises(ArgumentError) {
      draw do
        get "/foo/bar", action: :index
      end
    }
    assert_match(/Missing :controller/, ex.message)
  end

  def test_missing_controller_with_to
    ex = assert_raises(ArgumentError) {
      draw do
        get "/foo/bar", to: "foo"
      end
    }
    assert_match(/Missing :controller/, ex.message)
  end

  def test_implicit_controller_with_to
    draw do
      controller :foo do
        get "/foo/bar", to: "bar"
      end
    end
    assert_routing "/foo/bar", controller: "foo", action: "bar"
  end

  def test_to_is_a_symbol
    ex = assert_raises(ArgumentError) {
      draw do
        get "/foo/bar", to: :foo
      end
    }
    assert_match(/:to must respond to/, ex.message)
  end

  def test_missing_action_with_to
    ex = assert_raises(ArgumentError) {
      draw do
        get "/foo/bar", to: "foo#"
      end
    }
    assert_match(/Missing :action/, ex.message)
  end

  def test_valid_controller_options_inside_namespace
    draw do
      namespace :admin do
        resources :storage_files, controller: "storage_files"
      end
    end

    get "/admin/storage_files"
    assert_equal "admin/storage_files#index", @response.body
  end

  def test_resources_with_valid_namespaced_controller_option
    draw do
      resources :storage_files, controller: "admin/storage_files"
    end

    get "/storage_files"
    assert_equal "admin/storage_files#index", @response.body
  end

  def test_warn_with_ruby_constant_syntax_controller_option
    e = assert_raise(ArgumentError) do
      draw do
        namespace :admin do
          resources :storage_files, controller: "StorageFiles"
        end
      end
    end

    assert_match "'admin/StorageFiles' is not a supported controller name", e.message
  end

  def test_warn_with_ruby_constant_syntax_namespaced_controller_option
    e = assert_raise(ArgumentError) do
      draw do
        resources :storage_files, controller: "Admin::StorageFiles"
      end
    end

    assert_match "'Admin::StorageFiles' is not a supported controller name", e.message
  end

  def test_warn_with_ruby_constant_syntax_no_colons
    e = assert_raise(ArgumentError) do
      draw do
        resources :storage_files, controller: "Admin"
      end
    end

    assert_match "'Admin' is not a supported controller name", e.message
  end
end

class TestDefaultScope < ActionDispatch::IntegrationTest
  module ::Blog
    class PostsController < ActionController::Base
      def index
        render plain: "blog/posts#index"
      end
    end
  end

  DefaultScopeRoutes = ActionDispatch::Routing::RouteSet.new
  DefaultScopeRoutes.default_scope = { module: :blog }
  DefaultScopeRoutes.draw do
    resources :posts
  end

  APP = build_app DefaultScopeRoutes

  def app
    APP
  end

  include DefaultScopeRoutes.url_helpers

  def test_default_scope
    get "/posts"
    assert_equal "blog/posts#index", @response.body
  end
end

class TestHttpMethods < ActionDispatch::IntegrationTest
  RFC2616 = %w(OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT)
  RFC2518 = %w(PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK)
  RFC3253 = %w(VERSION-CONTROL REPORT CHECKOUT CHECKIN UNCHECKOUT MKWORKSPACE UPDATE LABEL MERGE BASELINE-CONTROL MKACTIVITY)
  RFC3648 = %w(ORDERPATCH)
  RFC3744 = %w(ACL)
  RFC5323 = %w(SEARCH)
  RFC4791 = %w(MKCALENDAR)
  RFC5789 = %w(PATCH)

  def simple_app(response)
    lambda { |env| [ 200, { "Content-Type" => "text/plain" }, [response] ] }
  end

  attr_reader :app

  def setup
    s = self
    routes = ActionDispatch::Routing::RouteSet.new
    @app = RoutedRackApp.new routes

    routes.draw do
      (RFC2616 + RFC2518 + RFC3253 + RFC3648 + RFC3744 + RFC5323 + RFC4791 + RFC5789).each do |method|
        match "/" => s.simple_app(method), :via => method.underscore.to_sym
      end
    end
  end

  (RFC2616 + RFC2518 + RFC3253 + RFC3648 + RFC3744 + RFC5323 + RFC4791 + RFC5789).each do |method|
    test "request method #{method.underscore} can be matched" do
      get "/", headers: { "REQUEST_METHOD" => method }
      assert_equal method, @response.body
    end
  end
end

class TestUriPathEscaping < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      get "/:segment" => lambda { |env|
        path_params = env["action_dispatch.request.path_parameters"]
        [200, { "Content-Type" => "text/plain" }, [path_params[:segment]]]
      }, :as => :segment

      get "/*splat" => lambda { |env|
        path_params = env["action_dispatch.request.path_parameters"]
        [200, { "Content-Type" => "text/plain" }, [path_params[:splat]]]
      }, :as => :splat
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  test "escapes slash in generated path segment" do
    assert_equal "/a%20b%2Fc+d", segment_path(segment: "a b/c+d")
  end

  test "unescapes recognized path segment" do
    get "/a%20b%2Fc+d"
    assert_equal "a b/c+d", @response.body
  end

  test "does not escape slash in generated path splat" do
    assert_equal "/a%20b/c+d", splat_path(splat: "a b/c+d")
  end

  test "unescapes recognized path splat" do
    get "/a%20b/c+d"
    assert_equal "a b/c+d", @response.body
  end
end

class TestUnicodePaths < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      get "/ほげ" => lambda { |env|
        [200, { "Content-Type" => "text/plain" }, []]
      }, :as => :unicode_path
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  test "recognizes unicode path" do
    get "/#{Rack::Utils.escape("ほげ")}"
    assert_equal "200", @response.code
  end
end

class TestMultipleNestedController < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      namespace :foo do
        namespace :bar do
          get "baz" => "baz#index"
        end
      end
      get "pooh" => "pooh#index"
    end
  end

  module ::Foo
    module Bar
      class BazController < ActionController::Base
        include Routes.url_helpers

        def index
          render inline: "<%= url_for :controller => '/pooh', :action => 'index' %>"
        end
      end
    end
  end

  APP = build_app Routes
  def app; APP end

  test "controller option which starts with '/' from multiple nested controller" do
    get "/foo/bar/baz"
    assert_equal "/pooh", @response.body
  end
end

class TestTildeAndMinusPaths < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/~user" => ok
      get "/young-and-fine" => ok
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  test "recognizes tilde path" do
    get "/~user"
    assert_equal "200", @response.code
  end

  test "recognizes minus path" do
    get "/young-and-fine"
    assert_equal "200", @response.code
  end
end

class TestRedirectInterpolation < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/foo/:id" => redirect("/foo/bar/%{id}")
      get "/bar/:id" => redirect(path: "/foo/bar/%{id}")
      get "/baz/:id" => redirect("/baz?id=%{id}&foo=?&bar=1#id-%{id}")
      get "/foo/bar/:id" => ok
      get "/baz" => ok
    end
  end

  APP = build_app Routes
  def app; APP end

  test "redirect escapes interpolated parameters with redirect proc" do
    get "/foo/1%3E"
    verify_redirect "http://www.example.com/foo/bar/1%3E"
  end

  test "redirect escapes interpolated parameters with option proc" do
    get "/bar/1%3E"
    verify_redirect "http://www.example.com/foo/bar/1%3E"
  end

  test "path redirect escapes interpolated parameters correctly" do
    get "/foo/1%201"
    verify_redirect "http://www.example.com/foo/bar/1%201"

    get "/baz/1%201"
    verify_redirect "http://www.example.com/baz?id=1+1&foo=?&bar=1#id-1%201"
  end

private
  def verify_redirect(url, status = 301)
    assert_equal status, @response.status
    assert_equal url, @response.headers["Location"]
    assert_equal "", @response.body
  end
end

class TestConstraintsAccessingParameters < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/:foo" => ok, :constraints => lambda { |r| r.params[:foo] == "foo" }
      get "/:bar" => ok
    end
  end

  APP = build_app Routes
  def app; APP end

  test "parameters are reset between constraint checks" do
    get "/bar"
    assert_nil @request.params[:foo]
    assert_equal "bar", @request.params[:bar]
  end
end

class TestGlobRoutingMapper < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/*id" => redirect("/not_cars"), :constraints => { id: /dummy/ }
      get "/cars" => ok
    end
  end

  # include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  def test_glob_constraint
    get "/dummy"
    assert_equal "301", @response.code
    assert_equal "/not_cars", @response.header["Location"].match("/[^/]+$")[0]
  end

  def test_glob_constraint_skip_route
    get "/cars"
    assert_equal "200", @response.code
  end
  def test_glob_constraint_skip_all
    get "/missing"
    assert_equal "404", @response.code
  end
end

class TestOptimizedNamedRoutes < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }
      get "/foo" => ok, as: :foo

      ActionDispatch.deprecator.silence do
        get "/post(/:action(/:id))" => ok, as: :posts
      end

      get "/:foo/:foo_type/bars/:id" => ok, as: :bar
      get "/projects/:id.:format" => ok, as: :project
      get "/pages/:id" => ok, as: :page
      get "/wiki/*page" => ok, as: :wiki
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  test "enabled when not mounted and default_url_options is empty" do
    assert_predicate Routes.url_helpers, :optimize_routes_generation?
  end

  test "named route called as singleton method" do
    assert_equal "/foo", Routes.url_helpers.foo_path
  end

  test "named route called on included module" do
    assert_equal "/foo", foo_path
  end

  test "nested optional segments are removed" do
    assert_equal "/post", Routes.url_helpers.posts_path
    assert_equal "/post", posts_path
  end

  test "segments with same prefix are replaced correctly" do
    assert_equal "/foo/baz/bars/1", Routes.url_helpers.bar_path("foo", "baz", "1")
    assert_equal "/foo/baz/bars/1", bar_path("foo", "baz", "1")
  end

  test "segments separated with a period are replaced correctly" do
    assert_equal "/projects/1.json", Routes.url_helpers.project_path(1, :json)
    assert_equal "/projects/1.json", project_path(1, :json)
  end

  test "segments with question marks are escaped" do
    assert_equal "/pages/foo%3Fbar", Routes.url_helpers.page_path("foo?bar")
    assert_equal "/pages/foo%3Fbar", page_path("foo?bar")
  end

  test "segments with slashes are escaped" do
    assert_equal "/pages/foo%2Fbar", Routes.url_helpers.page_path("foo/bar")
    assert_equal "/pages/foo%2Fbar", page_path("foo/bar")
  end

  test "glob segments with question marks are escaped" do
    assert_equal "/wiki/foo%3Fbar", Routes.url_helpers.wiki_path("foo?bar")
    assert_equal "/wiki/foo%3Fbar", wiki_path("foo?bar")
  end

  test "glob segments with slashes are not escaped" do
    assert_equal "/wiki/foo/bar", Routes.url_helpers.wiki_path("foo/bar")
    assert_equal "/wiki/foo/bar", wiki_path("foo/bar")
  end
end

class TestNamedRouteUrlHelpers < ActionDispatch::IntegrationTest
  class CategoriesController < ActionController::Base
    def show
      render plain: "categories#show"
    end
  end

  class ProductsController < ActionController::Base
    def show
      render plain: "products#show"
    end
  end

  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      scope module: "test_named_route_url_helpers" do
        get "/categories/:id" => "categories#show", :as => :category
        get "/products/:id" => "products#show", :as => :product
      end
    end
  end

  APP = build_app Routes
  def app; APP end

  include Routes.url_helpers

  test "URL helpers do not ignore nil parameters when using non-optimized routes" do
    Routes.stub :optimize_routes_generation?, false do
      get "/categories/1"
      assert_response :success
      assert_raises(ActionController::UrlGenerationError) { product_path(nil) }
    end
  end
end

class TestUrlConstraints < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      constraints subdomain: "admin" do
        get "/" => ok, :as => :admin_root
      end

      scope constraints: { protocol: "https://" } do
        get "/" => ok, :as => :secure_root
      end

      get "/" => ok, :as => :alternate_root, :constraints => { port: 8080 }

      get "/search" => ok, :constraints => { subdomain: false }

      get "/logs" => ok, :constraints => { subdomain: true }
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  test "constraints are copied to defaults when using constraints method" do
    assert_equal "http://admin.example.com/", admin_root_url

    get "http://admin.example.com/"
    assert_response :success
  end

  test "constraints are copied to defaults when using scope constraints hash" do
    assert_equal "https://www.example.com/", secure_root_url

    get "https://www.example.com/"
    assert_response :success
  end

  test "constraints are copied to defaults when using route constraints hash" do
    assert_equal "http://www.example.com:8080/", alternate_root_url

    get "http://www.example.com:8080/"
    assert_response :success
  end

  test "false constraint expressions check for absence of values" do
    get "http://example.com/search"
    assert_response :success
    assert_equal "http://example.com/search", search_url

    get "http://api.example.com/search"
    assert_response :not_found
  end

  test "true constraint expressions check for presence of values" do
    get "http://api.example.com/logs"
    assert_response :success
    assert_equal "http://api.example.com/logs", logs_url

    get "http://example.com/logs"
    assert_response :not_found
  end
end

class TestInvalidUrls < ActionDispatch::IntegrationTest
  class FooController < ActionController::Base
    param_encoding :show, :id, Encoding::ASCII_8BIT

    def show
      render plain: "foo#show"
    end
  end

  test "invalid UTF-8 encoding returns a bad request" do
    with_routing do |set|
      set.draw do
        get "/bar/:id", to: redirect("/foo/show/%{id}")

        ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }
        get "/foobar/:id", to: ok

        ActionDispatch.deprecator.silence do
          get "/:controller(/:action(/:id))"
        end
      end

      get "/%E2%EF%BF%BD%A6"
      assert_response :bad_request

      get "/foo/%E2%EF%BF%BD%A6"
      assert_response :bad_request

      get "/bar/%E2%EF%BF%BD%A6"
      assert_response :bad_request

      get "/foobar/%E2%EF%BF%BD%A6"
      assert_response :bad_request
    end
  end

  test "params param_encoding uses ASCII 8bit" do
    with_routing do |set|
      set.draw do
        get "/foo/show(/:id)", to: "test_invalid_urls/foo#show"
        get "/bar/show(/:id)", controller: "test_invalid_urls/foo", action: "show"
      end

      get "/foo/show/%E2%EF%BF%BD%A6"
      assert_response :ok

      get "/bar/show/%E2%EF%BF%BD%A6"
      assert_response :ok
    end
  end

  test "does not encode params besides id" do
    with_routing do |set|
      set.draw do
        get "/foo/show(/:id)", to: "test_invalid_urls/foo#show"
        get "/bar/show(/:id)", controller: "test_invalid_urls/foo", action: "show"
      end

      get "/foo/show/%E2%EF%BF%BD%A6?something_else=%E2%EF%BF%BD%A6"
      assert_response :bad_request

      get "/foo/show/%E2%EF%BF%BD%A6?something_else=%E2%EF%BF%BD%A6"
      assert_response :bad_request
    end
  end
end

class TestOptionalRootSegments < ActionDispatch::IntegrationTest
  stub_controllers do |routes|
    Routes = routes
    Routes.draw do
      get "/(page/:page)", to: "pages#index", as: :root
    end
  end

  APP = build_app Routes
  def app
    APP
  end

  include Routes.url_helpers

  def test_optional_root_segments
    get "/"
    assert_equal "pages#index", @response.body
    assert_equal "/", root_path

    get "/page/1"
    assert_equal "pages#index", @response.body
    assert_equal "1", @request.params[:page]
    assert_equal "/page/1", root_path("1")
    assert_equal "/page/1", root_path(page: "1")
  end
end

class TestPortConstraints < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/integer", to: ok, constraints: { port: 8080  }
      get "/string",  to: ok, constraints: { port: "8080" }
      get "/array/:idx",   to: ok, constraints: { port: [8080], idx: %w[first last] }
      get "/regexp",  to: ok, constraints: { port: /8080/ }
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  def test_integer_port_constraints
    get "http://www.example.com/integer"
    assert_response :not_found

    get "http://www.example.com:8080/integer"
    assert_response :success
  end

  def test_string_port_constraints
    get "http://www.example.com/string"
    assert_response :not_found

    get "http://www.example.com:8080/string"
    assert_response :success
  end

  def test_array_port_constraints
    get "http://www.example.com/array"
    assert_response :not_found

    get "http://www.example.com:8080/array/middle"
    assert_response :not_found

    get "http://www.example.com:8080/array/first"
    assert_response :success
  end

  def test_regexp_port_constraints
    get "http://www.example.com/regexp"
    assert_response :not_found

    get "http://www.example.com:8080/regexp"
    assert_response :success
  end
end

class TestFormatConstraints < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

      get "/string", to: ok, constraints: { format: "json"  }
      get "/regexp",  to: ok, constraints: { format: /json/ }
      get "/json_only", to: ok, format: true, constraints: { format: /json/ }
      get "/xml_only", to: ok, format: "xml"
    end
  end

  include Routes.url_helpers
  APP = build_app Routes
  def app; APP end

  def test_string_format_constraints
    get "http://www.example.com/string"
    assert_response :success

    get "http://www.example.com/string.json"
    assert_response :success

    get "http://www.example.com/string.html"
    assert_response :not_found
  end

  def test_regexp_format_constraints
    get "http://www.example.com/regexp"
    assert_response :success

    get "http://www.example.com/regexp.json"
    assert_response :success

    get "http://www.example.com/regexp.html"
    assert_response :not_found
  end

  def test_enforce_with_format_true_with_constraint
    get "http://www.example.com/json_only.json"
    assert_response :success

    get "http://www.example.com/json_only.html"
    assert_response :not_found

    get "http://www.example.com/json_only"
    assert_response :not_found
  end

  def test_enforce_with_string
    get "http://www.example.com/xml_only.xml"
    assert_response :success

    get "http://www.example.com/xml_only"
    assert_response :success

    get "http://www.example.com/xml_only.json"
    assert_response :not_found
  end
end

class TestCallableConstraintValidation < ActionDispatch::IntegrationTest
  def test_constraint_with_object_not_callable
    assert_raises(ArgumentError) do
      ActionDispatch::Routing::RouteSet.new.draw do
        ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }
        get "/test", to: ok, constraints: Object.new
      end
    end
  end
end

class TestRouteDefaults < ActionDispatch::IntegrationTest
  stub_controllers do |routes|
    Routes = routes
    Routes.draw do
      resources :posts, bucket_type: "post"
      resources :projects, defaults: { bucket_type: "project" }
    end
  end

  APP = build_app Routes
  def app
    APP
  end

  include Routes.url_helpers

  def test_route_options_are_required_for_url_for
    assert_raises(ActionController::UrlGenerationError) do
      url_for(controller: "posts", action: "show", id: 1, only_path: true)
    end

    assert_equal "/posts/1", url_for(controller: "posts", action: "show", id: 1, bucket_type: "post", only_path: true)
  end

  def test_route_defaults_are_not_required_for_url_for
    assert_equal "/projects/1", url_for(controller: "projects", action: "show", id: 1, only_path: true)
  end
end

class TestRackAppRouteGeneration < ActionDispatch::IntegrationTest
  stub_controllers do |routes|
    Routes = routes
    Routes.draw do
      rack_app = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }
      mount rack_app, at: "/account", as: "account"
      mount rack_app, at: "/:locale/account", as: "localized_account"
    end
  end

  APP = build_app Routes
  def app
    APP
  end

  include Routes.url_helpers

  def test_mounted_application_doesnt_match_unnamed_route
    assert_raise(ActionController::UrlGenerationError) do
      assert_equal "/account?controller=products", url_for(controller: "products", action: "index", only_path: true)
    end

    assert_raise(ActionController::UrlGenerationError) do
      assert_equal "/de/account?controller=products", url_for(controller: "products", action: "index", locale: "de", only_path: true)
    end
  end
end

class TestRedirectRouteGeneration < ActionDispatch::IntegrationTest
  stub_controllers do |routes|
    Routes = routes
    Routes.draw do
      get "/account", to: redirect("/myaccount"), as: "account"
      get "/:locale/account", to: redirect("/%{locale}/myaccount"), as: "localized_account"
    end
  end

  APP = build_app Routes
  def app
    APP
  end

  include Routes.url_helpers

  def test_redirect_doesnt_match_unnamed_route
    assert_raise(ActionController::UrlGenerationError) do
      assert_equal "/account?controller=products", url_for(controller: "products", action: "index", only_path: true)
    end

    assert_raise(ActionController::UrlGenerationError) do
      assert_equal "/de/account?controller=products", url_for(controller: "products", action: "index", locale: "de", only_path: true)
    end
  end
end

class TestUrlGenerationErrors < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      get "/products/:id" => "products#show", :as => :product
    end
  end

  APP = build_app Routes
  def app; APP end

  include Routes.url_helpers

  test "URL helpers raise a 'missing keys' error for a nil param with optimized helpers" do
    url, missing = { action: "show", controller: "products", id: nil }, [:id]
    message = "No route matches #{url.inspect}, missing required keys: #{missing.inspect}"

    error = assert_raises(ActionController::UrlGenerationError) { product_path(nil) }
    assert_equal message, error.message
  end

  test "URL helpers raise a 'constraint failure' error for a nil param with non-optimized helpers" do
    url, missing = { action: "show", controller: "products", id: nil }, [:id]
    message = "No route matches #{url.inspect}, possible unmatched constraints: #{missing.inspect}"

    error = assert_raises(ActionController::UrlGenerationError, message) { product_path(id: nil) }
    assert_match message, error.message
  end

  test "URL helpers raise message with mixed parameters when generation fails" do
    url, missing = { action: "show", controller: "products", id: nil, "id" => "url-tested" }, [:id]
    message = "No route matches #{url.inspect}, possible unmatched constraints: #{missing.inspect}"

    # Optimized URL helper
    error = assert_raises(ActionController::UrlGenerationError) { product_path(nil, "id" => "url-tested") }
    assert_match message, error.message

    # Non-optimized URL helper
    error = assert_raises(ActionController::UrlGenerationError, message) { product_path(id: nil, "id" => "url-tested") }
    assert_match message, error.message
  end

  test "exceptions have suggestions for fix" do
    error = assert_raises(ActionController::UrlGenerationError) { product_path(nil, "id" => "url-tested") }
    assert_match "Did you mean?", error.detailed_message
  end

  # FIXME: we should fix all locations that raise this exception to provide
  # the info DidYouMean needs and then delete this test.  Just adding the
  # test for now because some parameters to the constructor are optional, and
  # we don't want to break other code.
  test "correct for empty UrlGenerationError" do
    err = ActionController::UrlGenerationError.new("oh no!")

    assert_equal [], err.corrections
  end
end

class TestDefaultUrlOptions < ActionDispatch::IntegrationTest
  class PostsController < ActionController::Base
    def archive
      render plain: "posts#archive"
    end
  end

  Routes = ActionDispatch::Routing::RouteSet.new
  Routes.draw do
    default_url_options locale: "en"
    scope ":locale", format: false do
      get "/posts/:year/:month/:day", to: "posts#archive", as: "archived_posts"
    end
  end

  APP = build_app Routes

  def app
    APP
  end

  include Routes.url_helpers

  def test_positional_args_with_format_false
    assert_equal "/en/posts/2014/12/13", archived_posts_path(2014, 12, 13)
  end
end

class TestErrorsInController < ActionDispatch::IntegrationTest
  class ::PostsController < ActionController::Base
    def foo
      nil.i_do_not_exist
    end

    def bar
      NonExistingClass.new
    end
  end

  Routes = ActionDispatch::Routing::RouteSet.new
  Routes.draw do
    ActionDispatch.deprecator.silence do
      get "/:controller(/:action)"
    end
  end

  APP = build_app Routes

  def app
    APP
  end

  def test_legit_no_method_errors_are_not_caught
    get "/posts/foo"
    assert_equal 500, response.status
  end

  def test_legit_name_errors_are_not_caught
    get "/posts/bar"
    assert_equal 500, response.status
  end

  def test_legit_routing_not_found_responses
    get "/posts/baz"
    assert_equal 404, response.status

    get "/i_do_not_exist"
    assert_equal 404, response.status
  end
end

class TestPartialDynamicPathSegments < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new
  Routes.draw do
    ok = lambda { |env| [200, { "Content-Type" => "text/plain" }, []] }

    get "/songs/song-:song", to: ok
    get "/songs/:song-song", to: ok
    get "/:artist/song-:song", to: ok
    get "/:artist/:song-song", to: ok

    get "/optional/songs(/song-:song)", to: ok
    get "/optional/songs(/:song-song)", to: ok
    get "/optional/:artist(/song-:song)", to: ok
    get "/optional/:artist(/:song-song)", to: ok
  end

  APP = build_app Routes

  def app
    APP
  end

  def test_paths_with_partial_dynamic_segments_are_recognised
    get "/david-bowie/changes-song"
    assert_equal 200, response.status
    assert_params artist: "david-bowie", song: "changes"

    get "/david-bowie/song-changes"
    assert_equal 200, response.status
    assert_params artist: "david-bowie", song: "changes"

    get "/songs/song-changes"
    assert_equal 200, response.status
    assert_params song: "changes"

    get "/songs/changes-song"
    assert_equal 200, response.status
    assert_params song: "changes"

    get "/optional/songs/song-changes"
    assert_equal 200, response.status
    assert_params song: "changes"

    get "/optional/songs/changes-song"
    assert_equal 200, response.status
    assert_params song: "changes"

    get "/optional/david-bowie/changes-song"
    assert_equal 200, response.status
    assert_params artist: "david-bowie", song: "changes"

    get "/optional/david-bowie/song-changes"
    assert_equal 200, response.status
    assert_params artist: "david-bowie", song: "changes"
  end

  private
    def assert_params(params)
      assert_equal(params, request.path_parameters)
    end
end

class TestOptionalScopesWithOrWithoutParams < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      scope module: "test_optional_scopes_with_or_without_params" do
        scope "(:locale)", locale: /en|es/ do
          get "home", controller: :home, action: :index
          get "with_param/:foo", to: "home#with_param", as: "with_param"
          get "without_param", to: "home#without_param"
        end
      end
    end
  end

  class HomeController < ActionController::Base
    include Routes.url_helpers

    def index
      render inline: "<%= with_param_path(foo: 'bar') %> | <%= without_param_path %>"
    end

    def with_param; end
    def without_param; end
  end

  APP = build_app Routes

  def app
    APP
  end

  def test_stays_unscoped_with_or_without_params
    get "/home"
    assert_equal "/with_param/bar | /without_param", response.body
  end

  def test_preserves_scope_with_or_without_params
    get "/es/home"
    assert_equal "/es/with_param/bar | /es/without_param", response.body
  end
end

class TestPathParameters < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      scope module: "test_path_parameters" do
        scope ":locale", locale: /en|ar/ do
          root to: "home#index"
          get "/about", to: "pages#about"
        end
      end

      ActionDispatch.deprecator.silence do
        get ":controller(/:action/(:id))"
      end
    end
  end

  class HomeController < ActionController::Base
    include Routes.url_helpers

    def index
      render inline: "<%= root_path %>"
    end
  end

  class PagesController < ActionController::Base
    include Routes.url_helpers

    def about
      render inline: "<%= root_path(locale: :ar) %> | <%= url_for(locale: :ar) %>"
    end
  end

  APP = build_app Routes
  def app; APP end

  def test_path_parameters_are_not_mutated
    get "/en/about"
    assert_equal "/ar | /ar/about", @response.body
  end
end

class TestInternalRoutingParams < ActionDispatch::IntegrationTest
  Routes = ActionDispatch::Routing::RouteSet.new.tap do |app|
    app.draw do
      get "/test_internal/:internal" => "internal#internal"
    end
  end

  class ::InternalController < ActionController::Base
    def internal
      head :ok
    end
  end

  APP = build_app Routes

  def app
    APP
  end

  def test_paths_with_partial_dynamic_segments_are_recognised
    get "/test_internal/123"
    assert_equal 200, response.status

    assert_equal(
      { controller: "internal", action: "internal", internal: "123" },
      request.path_parameters
    )
  end
end

class FlashRedirectTest < ActionDispatch::IntegrationTest
  SessionKey = "_myapp_session"
  Generator = ActiveSupport::CachingKeyGenerator.new(
    ActiveSupport::KeyGenerator.new("b3c631c314c0bbca50c1b2843150fe33", iterations: 1000)
  )
  Rotations = ActiveSupport::Messages::RotationConfiguration.new
  SIGNED_COOKIE_SALT = "signed cookie"
  ENCRYPTED_SIGNED_COOKIE_SALT = "signed encrypted cookie"

  class KeyGeneratorMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      env["action_dispatch.key_generator"] ||= Generator
      env["action_dispatch.cookies_rotations"] ||= Rotations
      env["action_dispatch.signed_cookie_salt"] = SIGNED_COOKIE_SALT
      env["action_dispatch.encrypted_signed_cookie_salt"] = ENCRYPTED_SIGNED_COOKIE_SALT

      @app.call(env)
    end
  end

  class FooController < ActionController::Base
    def bar
      render plain: (flash[:foo] || "foo")
    end
  end

  Routes = ActionDispatch::Routing::RouteSet.new
  Routes.draw do
    get "/foo", to: redirect { |params, req| req.flash[:foo] = "bar"; "/bar" }
    get "/bar", to: "flash_redirect_test/foo#bar"
  end

  APP = build_app Routes do |middleware|
    middleware.use KeyGeneratorMiddleware
    middleware.use ActionDispatch::Session::CookieStore, key: SessionKey
    middleware.use ActionDispatch::Flash
    middleware.delete ActionDispatch::ShowExceptions
  end

  def app
    APP
  end

  include Routes.url_helpers

  def test_block_redirect_commits_flash
    get "/foo", env: { "action_dispatch.key_generator" => Generator }
    assert_response :redirect

    follow_redirect!
    assert_equal "bar", response.body
  end
end

class TestRecognizePath < ActionDispatch::IntegrationTest
  class PageConstraint
    attr_reader :key, :pattern

    def initialize(key, pattern)
      @key = key
      @pattern = pattern
    end

    def matches?(request)
      pattern.match?(request.path_parameters[key])
    end
  end

  stub_controllers do |routes|
    Routes = routes
    routes.draw do
      get "/hash/:foo", to: "pages#show", constraints: { foo: /foo/ }
      get "/hash/:bar", to: "pages#show", constraints: { bar: /bar/ }

      get "/proc/:foo", to: "pages#show", constraints: proc { |r| /foo/.match?(r.path_parameters[:foo]) }
      get "/proc/:bar", to: "pages#show", constraints: proc { |r| /bar/.match?(r.path_parameters[:bar]) }

      get "/class/:foo", to: "pages#show", constraints: PageConstraint.new(:foo, /foo/)
      get "/class/:bar", to: "pages#show", constraints: PageConstraint.new(:bar, /bar/)
    end
  end

  APP = build_app Routes
  def app
    APP
  end

  def test_hash_constraints_dont_leak_between_routes
    expected_params = { controller: "pages", action: "show", bar: "bar" }
    actual_params = recognize_path("/hash/bar")

    assert_equal expected_params, actual_params
  end

  def test_proc_constraints_dont_leak_between_routes
    expected_params = { controller: "pages", action: "show", bar: "bar" }
    actual_params = recognize_path("/proc/bar")

    assert_equal expected_params, actual_params
  end

  def test_class_constraints_dont_leak_between_routes
    expected_params = { controller: "pages", action: "show", bar: "bar" }
    actual_params = recognize_path("/class/bar")

    assert_equal expected_params, actual_params
  end

  private
    def recognize_path(*args)
      Routes.recognize_path(*args)
    end
end

class TestRelativeUrlRootGeneration < ActionDispatch::IntegrationTest
  config = ActionDispatch::Routing::RouteSet::Config.new("/blog", false)

  stub_controllers(config) do |routes|
    Routes = routes

    routes.draw do
      get "/", to: "posts#index", as: :posts
      get "/:id", to: "posts#show", as: :post
    end
  end

  include Routes.url_helpers

  APP = build_app Routes

  def app
    APP
  end

  def test_url_helpers
    assert_equal "/blog/", posts_path({})
    assert_equal "/blog/", Routes.url_helpers.posts_path({})

    assert_equal "/blog/1", post_path(id: "1")
    assert_equal "/blog/1", Routes.url_helpers.post_path(id: "1")
  end

  def test_optimized_url_helpers
    assert_equal "/blog/", posts_path
    assert_equal "/blog/", Routes.url_helpers.posts_path

    assert_equal "/blog/1", post_path("1")
    assert_equal "/blog/1", Routes.url_helpers.post_path("1")
  end
end
