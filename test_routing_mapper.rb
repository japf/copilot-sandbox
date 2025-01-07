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
