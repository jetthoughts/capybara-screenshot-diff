# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "actionpack", "~> 6.0.1", "< 6.1"
gem "capybara", ">= 2.15"
gem "selenium-webdriver"
