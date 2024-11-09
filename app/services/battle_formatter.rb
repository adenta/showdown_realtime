class BattleFormatter
  def self.format_battle(battle_state)
    @logger = ColorLogger.new(Rails.root.join('log', 'asyncstreamer.log'))
    @logger.progname = 'BAFO'

    battle_state = battle_state.deep_symbolize_keys!
    formatted_battle_state = "Battle State (Turn #{battle_state[:rqid].to_i / 2.to_f}):\n\n"

    battle_state[:active].each do |active_pokemon|
      formatted_battle_state += "Active Pokemon:\n"
      formatted_battle_state += "  Moves:\n"
      active_pokemon[:moves].each do |move|
        formatted_battle_state += "    - #{move[:move]} (PP: #{move[:pp]}/#{move[:maxpp]}, Target: #{move[:target]}, Disabled: #{move[:disabled]})\n"
      end
      formatted_battle_state += "  Can Terastallize: #{active_pokemon[:canTerastallize]}\n\n"
    end

    formatted_battle_state += "Side:\n"
    formatted_battle_state += "  Name: #{battle_state[:side][:name]}\n"
    formatted_battle_state += "  ID: #{battle_state[:side][:id]}\n"
    formatted_battle_state += "  Pokemon:\n"
    battle_state[:side][:pokemon].each do |pokemon|
      formatted_battle_state += "    - #{pokemon[:ident]} (#{pokemon[:details]})\n"
      formatted_battle_state += "      Condition: #{pokemon[:condition]}\n"
      formatted_battle_state += "      Stats: Atk: #{pokemon[:stats][:atk]}, Def: #{pokemon[:stats][:def]}, Spa: #{pokemon[:stats][:spa]}, Spd: #{pokemon[:stats][:spd]}, Spe: #{pokemon[:stats][:spe]}\n"
      formatted_battle_state += "      Moves: #{pokemon[:moves].join(', ')}\n"
      formatted_battle_state += "      Base Ability: #{pokemon[:baseAbility]}\n"
      formatted_battle_state += "      Item: #{pokemon[:item]}\n"
      formatted_battle_state += "      Ability: #{pokemon[:ability]}\n"
      formatted_battle_state += "      Commanding: #{pokemon[:commanding]}\n"
      formatted_battle_state += "      Reviving: #{pokemon[:reviving]}\n"
    end

    formatted_battle_state
  rescue StandardError => e
    @logger.error "Error formatting battle: #{e}"
  end
end
