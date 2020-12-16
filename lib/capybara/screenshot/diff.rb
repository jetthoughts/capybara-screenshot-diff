# frozen_string_literal: true

require "capybara/dsl"
require "capybara/screenshot/diff/version"
require "capybara/screenshot/diff/drivers/utils"
require "capybara/screenshot/diff/image_compare"
require "capybara/screenshot/diff/test_methods"

module Capybara
  module Screenshot
    extend Os
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path
    mattr_accessor :blur_active_element
    mattr_accessor :enabled
    mattr_accessor :hide_caret
    mattr_reader(:root) { (defined?(Rails.root) && Rails.root) || Pathname(".").expand_path }
    mattr_accessor :stability_time_limit
    mattr_accessor :window_size
    mattr_accessor(:save_path) { "doc/screenshots" }
    mattr_accessor(:use_lfs)

    class << self
      def root=(path)
        @@root = Pathname(path).expand_path
      end

      def active?
        enabled || (enabled.nil? && Diff.enabled)
      end

      def screenshot_area
        parts = [Capybara::Screenshot.save_path]
        parts << Capybara.current_driver.to_s if Capybara::Screenshot.add_driver_path
        parts << os_name if Capybara::Screenshot.add_os_path
        File.join parts
      end

      def screenshot_area_abs
        root / screenshot_area
      end
    end

    # Module to track screen shot changes
    module Diff
      include Capybara::DSL
      include Capybara::Screenshot::Os

      mattr_accessor :area_size_limit
      mattr_accessor :color_distance_limit
      mattr_accessor(:enabled) { true }
      mattr_accessor :shift_distance_limit
      mattr_accessor :skip_area
      mattr_accessor(:driver) { :auto }
      mattr_accessor(:tolerance) { 0.001 }

      AVAILABLE_DRIVERS = Utils.detect_available_drivers.freeze

      def self.included(klass)
        klass.include TestMethods
        klass.setup do
          if Capybara::Screenshot.window_size
            if page.driver.respond_to?(:resize)
              page.driver.resize(*Capybara::Screenshot.window_size)
            elsif selenium?
              page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
            end
          end
        end

        klass.teardown do
          if Capybara::Screenshot::Diff.enabled && @test_screenshots
            test_screenshot_errors = @test_screenshots
              .map { |caller, name, compare| assert_image_not_changed(caller, name, compare) }
            test_screenshot_errors.compact!
            fail(test_screenshot_errors.join("\n\n")) if test_screenshot_errors.any?
          end
        end
      end
    end
  end
end
