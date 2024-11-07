require 'async'
require 'async/http'
require 'async/websocket'
require 'openssl'
require 'base64'
require 'json'

class InochiOscService
  URL = ENV['OBS_WEBSOCKET_URL']
  GAMEPLAY_SCENE = 'gameplay'
  PAUSE_SCENE = 'pause'

  def initialize
    @osc_client = OSC::Client.new('localhost', 39_540)

    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'INOC'
  end

  def open_connection
    Async do |task|
      loop do
        if rand > 0.95
          @logger.info('blinking')
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkLeft', 1.to_f))
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkRight', 1.to_f))
          task.sleep 0.15
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkLeft', 0.to_f))
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkRight', 0.to_f))
          task.sleep 0.5

        end

        if rand > 0.5
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'psHeadLeftRight', [-0.01, 0.0, 0.01].sample))
          @osc_client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'psHeadRoll', [-0.01, 0.0, 0.01].sample))
        end

        task.sleep 0.1

        # next unless talking_at && (Time.zone.now - talking_at < 0.1.seconds)

        # variable = 'ftMouthOpen'
        # value = 0.5

        # message = OSC::Message.new('/VMC/Ext/Blend/Val', variable, value)
        # @osc_client.send(message)
      end
    end
  end
end
