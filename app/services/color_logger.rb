class ColorLogger < Logger
  def initialize(logdev)
    super
    @formatter = proc do |severity, datetime, progname, msg|
      colorized_message = case progname
                          when 'OBS' then msg.to_s.green
                          when 'PKMN' then msg.to_s.red
                          when 'OPENAI' then msg.to_s.blue
                          else msg.to_s
                          end
      "#{colorized_message}\n"
    end
  end
end
