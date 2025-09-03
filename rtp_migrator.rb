#~ Automatically copies missing RTP resources referenced in game data
#~ For https://github.com/Admenri/urge
#~ Made by YokiiDev

module FileUtils
  def self.mkdir_p(path)
    parts = path.gsub("\\", "/").split("/")
    current_path = path.start_with?("/") ? "/" : ""
    
    parts.each do |part|
      next if part.empty?
      current_path = current_path == "/" ? "/#{part}" : 
                     current_path.empty? ? part : 
                     File.join(current_path, part)
      
      begin
        Dir.mkdir(current_path) unless File.directory?(current_path)
      rescue Errno::EEXIST
      end
    end
  end

  def self.cp(source, dest)
    File.open(source, 'rb') do |src|
      File.open(dest, 'wb') do |dst|
        while (chunk = src.read(16384))
          dst.write(chunk)
        end
      end
    end
  end
end


#~ https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights
#~ https://www.rubydoc.info/stdlib/win32/2.1.6/Win32/Registry/Constants
module RTP_Migrator
  HKEY_LOCAL_MACHINE = 0x80000002
  KEY_READ = 0x20019
  
  RegOpenKeyEx    = Win32API.new('advapi32', 'RegOpenKeyExA', 'LPLLP', 'L')
  RegQueryValueEx = Win32API.new('advapi32', 'RegQueryValueExA', 'LPLPPP', 'L')
  RegCloseKey     = Win32API.new('advapi32', 'RegCloseKey', 'L', 'L')
  
  def self.get_rtp_path
    keys_to_try = [
      'SOFTWARE\\WOW6432Node\\Enterbrain\\RGSS3\\RTP',
      'SOFTWARE\\Enterbrain\\RGSS3\\RTP'
    ]
    keys_to_try.each do |key_path|
      path = query_registry(key_path, 'RPGVXAce')
      return path if path
    end
    nil
  end
  
  def self.query_registry(key_path, value_name)
    hKey = [0].pack('L')
    result = RegOpenKeyEx.call(HKEY_LOCAL_MACHINE, key_path, 0, KEY_READ, hKey)
    return nil if result != 0
    
    hKey = hKey.unpack('L').first
    reg_type = [0].pack('L')
    buffer_size = [0].pack('L')
    
    RegQueryValueEx.call(hKey, value_name, 0, reg_type, nil, buffer_size)
    actual_size = buffer_size.unpack('L').first
    return nil if actual_size == 0
    
    buffer = "\0" * actual_size
    buffer_size = [buffer.size].pack('L')
    result = RegQueryValueEx.call(hKey, value_name, 0, reg_type, buffer, buffer_size)
    RegCloseKey.call(hKey)
    
    return nil if result != 0
    path = buffer.unpack('Z*').first
    return path && !path.empty? ? path : nil
  end
  
  @assets = {
    :animation => {}, :battleback1 => {}, :battleback2 => {},
    :battler => {}, :character => {}, :face => {},
    :parallax => {}, :picture => {}, :system => {},
    :tileset => {}, :title1 => {}, :title2 => {},
    :bgm => {}, :bgs => {}, :me => {}, :se => {}
  }

  @asset_folders = {
    :animation => "Graphics/Animations/", :battleback1 => "Graphics/Battlebacks1/",
    :battleback2 => "Graphics/Battlebacks2/", :battler => "Graphics/Battlers/",
    :character => "Graphics/Characters/", :face => "Graphics/Faces/",
    :parallax => "Graphics/Parallaxes/", :picture => "Graphics/Pictures/",
    :system => "Graphics/System/", :tileset => "Graphics/Tilesets/",
    :title1 => "Graphics/Titles1/", :title2 => "Graphics/Titles2/",
    :bgm => "Audio/BGM/", :bgs => "Audio/BGS/",
    :me => "Audio/ME/", :se => "Audio/SE/"
  }

  @asset_extensions = {
    :graphics => ['.png', '.jpg', '.jpeg'],
    :audio => ['.ogg', '.wav', '.mp3', '.mid']
  }

  @standard_system_files = [
    'Balloon', 'BattleStart', 'GameOver', 'IconSet', 'Shadow', 'Window'
  ]

  def self.get_extensions_for_type(type)
    @asset_folders[type].start_with?("Graphics") ? @asset_extensions[:graphics] : @asset_extensions[:audio]
  end

  def self.add_asset(type, filename)
    return if filename.nil? || filename.empty?
    @assets[type][filename] = true
  end

  def self.run
    puts "Starting RTP Migration..."
    @rtp_path = get_rtp_path
    unless @rtp_path && File.directory?(@rtp_path)
      puts "Error: Could not find valid RTP path."
      return
    end
    puts "RTP path found: #{@rtp_path}"
    
    scan_all_data
    process_all_assets
    puts "RTP Migration completed."
  end

  def self.scan_all_data
    DataManager.load_normal_database
    
    scan_database($data_actors, :actor)
    scan_database($data_classes, :class)
    scan_database($data_skills, :skill)
    scan_database($data_items, :item)
    scan_database($data_weapons, :weapon)
    scan_database($data_armors, :armor)
    scan_database($data_enemies, :enemy)
    scan_database($data_animations, :animation)
    scan_database($data_tilesets, :tileset)
    scan_database($data_common_events, :common_event)
    scan_database($data_troops, :troop)
    
    scan_system($data_system)
    
    @standard_system_files.each { |filename| add_asset(:system, filename) }
    
    Dir.glob("Data/Map*.rvdata2").each do |filename|
      map_data = load_data(filename)
      scan_map(map_data)
    end
  end
  
  def self.scan_database(data_array, type)
    return unless data_array.is_a?(Array)
    data_array.each do |data|
      next if data.nil?
      case type
      when :actor then scan_actor(data)
      when :animation then scan_animation(data)
      when :enemy then scan_enemy(data)
      when :tileset then scan_tileset(data)
      when :common_event then scan_event_list(data.list)
      when :troop then data.pages.each { |page| scan_event_list(page.list) }
      end
    end
  end

  def self.scan_actor(actor)
    add_asset(:character, actor.character_name)
    add_asset(:face, actor.face_name)
  end

  def self.scan_animation(anim)
    add_asset(:animation, anim.animation1_name)
    add_asset(:animation, anim.animation2_name)
    anim.timings.each { |timing| add_asset(:se, timing.se.name) }
  end
  
  def self.scan_enemy(enemy)
    add_asset(:battler, enemy.battler_name)
  end
  
  def self.scan_tileset(tileset)
    tileset.tileset_names.each { |name| add_asset(:tileset, name) }
  end

  def self.scan_system(system)
    add_asset(:battler, system.battler_name)
    add_asset(:title1, system.title1_name)
    add_asset(:title2, system.title2_name)
    add_asset(:bgm, system.title_bgm.name)
    add_asset(:bgm, system.battle_bgm.name)
    add_asset(:me, system.battle_end_me.name)
    add_asset(:me, system.gameover_me.name)
    system.sounds.each { |se| add_asset(:se, se.name) }
    [:boat, :ship, :airship].each do |v_sym|
      vehicle = system.send(v_sym)
      add_asset(:character, vehicle.character_name)
      add_asset(:bgm, vehicle.bgm.name)
    end
  end
 
  def self.scan_map(map)
    return unless map.is_a?(RPG::Map)
    add_asset(:battleback1, map.battleback1_name)
    add_asset(:battleback2, map.battleback2_name)
    add_asset(:bgm, map.bgm.name)
    add_asset(:bgs, map.bgs.name)
    add_asset(:parallax, map.parallax_name)
    
    return if map.events.nil?
    map.events.each_value do |event|
      next if event.nil?
      event.pages.each do |page|
        add_asset(:character, page.graphic.character_name)
        scan_event_list(page.list)
      end
    end
  end

  def self.scan_event_list(list)
    return if list.nil?
    list.each do |command|
      params = command.parameters
      case command.code
      when 231 then add_asset(:picture, params[1])
      when 241 then add_asset(:bgm, params[0].name)
      when 245 then add_asset(:bgs, params[0].name)
      when 249 then add_asset(:me, params[0].name)
      when 250 then add_asset(:se, params[0].name)
      when 283
        add_asset(:battleback1, params[0])
        add_asset(:battleback2, params[1])
      when 284 then add_asset(:parallax, params[0])
      when 322
        add_asset(:character, params[1])
        add_asset(:face, params[3])
      when 323 then add_asset(:character, params[1])
      end
    end
  end
  
  def self.process_all_assets
    @assets.each do |type, files|
      next if files.empty?
      files.keys.each { |filename| process_file(type, @asset_folders[type], filename) }
    end
  end
  
  def self.process_file(type, relative_path, filename)
    get_extensions_for_type(type).each do |ext|
      return if File.exist?(relative_path + filename + ext)
    end
    
    found_source_path = nil
    found_ext = nil
    get_extensions_for_type(type).each do |ext|
      source_path_with_ext = File.join(@rtp_path, relative_path, filename + ext)
      if File.exist?(source_path_with_ext)
        found_source_path = source_path_with_ext
        found_ext = ext
        break
      end
    end
    
    if found_source_path
      dest_path_with_ext = relative_path + filename + found_ext
      puts "Copying: #{filename}#{found_ext}"
      begin
        FileUtils.mkdir_p(relative_path)
        FileUtils.cp(found_source_path, dest_path_with_ext)
      rescue => e
        puts "Error copying: #{e.message}"
      end
    else
      puts "Not found: #{filename}"
    end
  end
end

RTP_Migrator.run
