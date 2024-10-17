module AudioModeHelper
  def audio_mode_puts(message)
    puts message unless ENV['AUDIO_MODE'] == 'true'
  end
end
