class ColorLogger < Logger
  def initialize(logdev)
    super
    @formatter = proc do |severity, datetime, progname, msg|
      colorized_message = case progname
                          when 'OBS' then msg.to_s.white
                          when 'PKMN' then msg.to_s.red
                          when 'OAIVO' then msg.to_s.blue
                          when 'OAICM' then msg.to_s.purple
                          when 'COMM' then msg.to_s.yellow
                          when 'ASYN' then msg.to_s.cyan
                          when 'TWITC' then msg.to_s.green
                          else msg.to_s
                          end
      "#{colorized_message}\n"
    end
  end
end
