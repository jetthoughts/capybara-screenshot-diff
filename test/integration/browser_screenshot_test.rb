require "test_helper"

# Capybara.app = Rack::Builder.new do
#   puts "Creating static rack server serving"
#   run(Rack::Static, urls: "/", root: Pathname.new('test/fixtures/'))
# end.to_app

# Setup for Capybara to test Jekyll static files served by Rack
require 'capybara/dsl'

Capybara.app = Rack::Builder.new do
  use(Rack::Static, urls: [""], root: "test/fixtures/app", index: "index.html")
  run ->(_env) { [200, {}, []] }
end.to_app

Capybara.current_driver = :selenium_chrome_headless

class BrowserScreenshotTest < ActionDispatch::IntegrationTest
  include Capybara::Screenshot::Diff

  # TODO: Allow to test with different drivers
  # driven_by :selenium, using: :chrome, screen_size: Capybara::Screenshot.window_size
  # driven_by :selenium, using: :headless_chrome, screen_size: Capybara::Screenshot.window_size

  def test_screenshot_in_real_browser
    Capybara::Screenshot.save_path = 'fixtures/screenshots'
    Capybara::Screenshot.enabled = true
    Capybara::Screenshot::Diff.enabled = true

    Capybara::Screenshot.add_os_path = true
    Capybara::Screenshot.add_driver_path = true
    Capybara::Screenshot.window_size = [800, 600]

    visit '/index.html'
    screenshot 'index'
  end
end
