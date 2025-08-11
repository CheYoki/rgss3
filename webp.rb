module WebPLoader
  DLL = "system/webp_loader.dll"
  begin
    GetInfo = Win32API.new(DLL, 'get_webp_info', 'PPP', 'L')
    Decode = Win32API.new(DLL, 'decode_webp_to_bitmap', 'PPL', 'L')
    @loaded = true
    puts "WebP DLL loaded."
  rescue => e
    puts "[ERROR] Failed to load '#{DLL}': #{e.message}"
    @loaded = false
  end
  def self.enabled?; @loaded; end
end

class Bitmap
  unless method_defined?(:last_row_address)
    RtlMoveMemory = Win32API.new('kernel32', 'RtlMoveMemory', 'ppi', 'i')
    def last_row_address
      return 0 if disposed?
      buf = [0].pack('L')
      RtlMoveMemory.call(buf, __id__ * 2 + 16, 4)
      RtlMoveMemory.call(buf, buf.unpack('L')[0] + 8, 4)
      RtlMoveMemory.call(buf, buf.unpack('L')[0] + 16, 4)
      buf.unpack('L')[0]
    end
  end

  alias_method :orig_init, :initialize
  def initialize(*args)
    if WebPLoader.enabled? && args[0].is_a?(String)
      file = args[0]
      webp = file.downcase.end_with?('.webp') ? file : 
             File.exist?(file + '.webp') ? file + '.webp' : nil
      
      if webp
        w, h = [0].pack('l!'), [0].pack('l!')
        if WebPLoader::GetInfo.call(webp, w, h) == 0
          orig_init(w.unpack('l!')[0], h.unpack('l!')[0])
          ptr = last_row_address
          if ptr != 0
            WebPLoader::Decode.call(webp, ptr, width * height * 4)
          else
            puts "[ERROR] Could not get bitmap address"
          end
        else
          puts "WebP Error: #{webp}"
          orig_init(32, 32)
        end
      else
        orig_init(*args)
      end
    else
      orig_init(*args)
    end
  end
end