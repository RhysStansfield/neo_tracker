require 'pry'
require 'net/http'
require 'json'
require 'curses'

module NeoTracker
  def self.run
    Curses.cbreak
    Curses.init_screen

    begin
      Cli::Application.new(Curses.stdscr, Curses.cols, Curses.lines).run
    ensure
      Curses.close_screen
    end
  end

  module Cli
    class Application
      INVALID_OPTION_STRING = 'Invalid option selected, please try again:'
      OPTIONS = {
        'f' => '::NeoTracker::Cli::Application::NeoFeed',
        'l' => '::NeoTracker::Cli::Application::NeoLookup'
      }.freeze

      attr_accessor :window, :cols, :lines, :margin_x, :margin_y

      def initialize(window, cols, lines)
        self.window = window
        self.cols = cols
        self.lines = lines
        self.margin_x = 3
        self.margin_y = 3
      end

      def clear
        window.clear
        window.refresh
      end

      def current_x
        window.curx
      end

      def current_y
        window.cury
      end

      def emulate_typing(msg, interval)
        msg.each_char do |char|
          window.addch(char)
          window.refresh
          sleep(interval)
        end
      end

      def get_option
        option = OPTIONS[input = window.getch]
        return [input, Object.const_get(option)] if option

        newline
        print_out(INVALID_OPTION_STRING)
        newline

        get_option
      end

      def get_string
        window.getstr
      end

      def newline
        set_cursor_position(current_y + 1, margin_x)
      end

      def print_out(msg)
        window.addstr(msg)
        window.refresh
      end

      def run
        box
        window.setpos(margin_y, margin_x)
        welcome_screen

        input, option = get_option

        newline
        print_out("You selected #{input}")
        newline

        option.new(self).run

        sleep(2)
      end

      def set_cursor_position(y, x)
        window.setpos(y, x)
      end

      private

      def box
        window.box(?|, ?-)
      end

      def initialize_cursor
        window.setpos(margin_y, margin_x)
      end

      def welcome_screen
        WelcomeScreen.new(self).run
      end

      class WelcomeScreen
        attr_accessor :app

        WELCOME_STRING = "NEO (Near Earth Object) Tracker".freeze
        OPTIONS_STRING = "Options:".freeze
        OPTIONS = {
          'f' => 'Retrieve NEO data feed (will provide start and end date options)'.freeze,
          'l' => 'Lookup NEO by ID'.freeze
        }.freeze

        def initialize(app)
          self.app = app
        end

        def run
          app.emulate_typing(WELCOME_STRING, 0.01)

          sleep(0.3)

          app.newline
          app.emulate_typing(OPTIONS_STRING, 0.01)

          sleep(0.3)

          OPTIONS.each_pair do |key, value|
            app.set_cursor_position(app.current_y + 1, app.margin_x + 4)
            app.print_out("#{key}: #{value}")

            sleep(0.3)
          end

          app.newline
        end
      end

      class NeoFeed
        attr_accessor :app, :api_key, :start_date, :end_date, :data

        def initialize(app)
          self.app = app
          self.api_key = ENV['NASA_API_KEY'] || 'DEMO_KEY'
        end

        def run
          app.print_out("Enter start date (YYYY-MM-DD) - leave blank to start from now:")
          app.newline
          start_date_str = app.get_string
          app.newline

          self.start_date = start_date_str if valid_date?(start_date_str)

          app.print_out("Enter end date (YYYY-MM-DD) - leave blank to default to 7 days from start date:")
          app.newline
          end_date_string = app.get_string
          app.newline

          self.end_date = end_date_string if valid_date?(end_date_string)

          fetch_data

          app.print_out("Fetched data")
          app.newline
          app.print_out(data.keys.join('|'))
        end

        private

        def fetch_data
          url = "https://api.nasa.gov/neo/rest/v1/feed?api_key=#{api_key}"
          url += "&start_date=#{start_date}" if start_date
          url += "&end_date=#{end_date}" if end_date
          uri = URI(url)

          Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
            self.data = JSON.parse(http.request(Net::HTTP::Get.new(uri)).body)
          end
        end

        def valid_date?(date_str)
          !!(date_str.match(/\d{4}-\d{2}-\d{2}/) && Date.parse(date_str))
        rescue ArgumentError
          false
        end
      end

      class NeoLookup
        attr_accessor :app, :api_key, :neo_id, :data

        def initialize(app)
          self.app = app
          self.api_key = ENV['NASA_API_KEY'] || 'DEMO_KEY'
        end

        def run
          app.print_out("Enter id of NEO to inspect")
          app.newline
          self.neo_id = app.get_string
          app.newline

          fetch_data

          if data
            app.print_out("Fetched data")
            app.newline
            app.print_out(data.keys.join('|'))
          end
        end

        private

        def fetch_data
          url = "https://api.nasa.gov/neo/rest/v1/neo/#{neo_id}?api_key=#{api_key}"
          uri = URI(url)

          Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
            response = http.request(Net::HTTP::Get.new(uri))

            case response
            when Net::HTTPNotFound then handle_error
            when Net::HTTPSuccess then self.data = JSON.parse(response.body)
            end
          end
        end

        def handle_error
          app.newline
          app.print_out("Couldn't find NEO with that ID!")
        end
      end
    end
  end
end

NeoTracker.run
