require 'net/imap'

module Mailman
  module Receiver
    # Receives messages using IMAP, and passes them to a {MessageProcessor}.
    class IMAP

      # @return [Net::IMAP] the IMAP connection
      attr_reader :connection

      # @param [Hash] options the receiver options
      # @option options [MessageProcessor] :processor the processor to pass new
      #   messages to
      # @option options [String] :server the server to connect to
      # @option options [Integer] :port the port to connect to
      # @option options [Boolean] :ssl whether or not to use ssl
      # @option options [String] :username the username to authenticate with
      # @option options [String] :password the password to authenticate with
      # @option options [String] :folder the mail folder to search
      # @option options [Array] :done_flags the flags to add to messages that
      #   have been processed
      # @option options [Array] :clear_flags the flags to clear from messages
      #   that have been processed
      # @option options [String] :filter the search filter to use to select
      #   messages to process
      # @option options [Proc] :on_login the block, that be called when we
      #   successfully logged in to server
      # @option options [boolean] :one_time_connect whether or not to connect
      #   only once to the server. Set it to false for a default behaviour
      def initialize(options)
        @processor  = options[:processor]
        @server     = options[:server]
        @username   = options[:username]
        @password   = options[:password]
        @filter     = options[:filter] || 'UNSEEN'
        @done_flags = options[:done_flags] || [Net::IMAP::SEEN]
        @clear_flags = options[:clear_flags]
        @port       = options[:port] || 143
        @ssl        = options[:ssl] || false
        @folder     = options[:folder] || "INBOX"
        @expunge    = options[:expunge] || true
        @on_login_block = options[:on_login]
        @one_time   = options[:one_time_connect] || false
      end

      # Connects to the IMAP server.
      def connect
        if @connection.nil? or @connection.disconnected?
          @connection = Net::IMAP.new(@server, port: @port, ssl: @ssl)
          @connection.login(@username, @password)
          @on_login_block.call(self) if @on_login_block.present?
        end
        @connection.select(@folder)
      end

      # Disconnects from the IMAP server.
      def disconnect(force = false)
        return true if @connection.nil? || @connection.disconnected?
        # do not disconnect, if we in one-time-connect mode
        if !@one_time || force
          @connection.logout
          @connection.disconnected? ? true : @connection.disconnect rescue nil
        end
      end

      # Iterates through new messages, passing them to the processor, and
      # flagging them as done.
      def get_messages
        begin
          @connection.search(@filter).each do |message|
            fetch_data = @connection.fetch(message, "RFC822")[0]
            body = fetch_data.attr["RFC822"]
            @processor.process(body, self, fetch_data)
            @connection.store(message, '+FLAGS', @done_flags) unless @done_flags.blank?
            @connection.store(message, '-FLAGS', @clear_flags) unless @clear_flags.blank?
          end
          # Clears messages that have the Deleted flag set
          @connection.expunge if @expunge
        rescue NoMethodError
          # just ignore errors like .../lib/ruby/1.9.1/net/imap.rb:1332:in
          # `block in search_internal': undefined method `[]' for nil:NilClass
          # (NoMethodError)
          # It's encountered when the searchable mailbox folder
          # (INBOX by default) is empty
        rescue StandardError => error
          Mailman.logger.error "Error encountered while receiving messages from IMAP: #{error.class.to_s}: #{error.message}\n #{error.backtrace.join("\n")}"
        end
      end

    end
  end
end
