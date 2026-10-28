///|
/// Normalize PNG's IDAT stream to stored deflate blocks on Node.js. The image
/// decoder remains MoonBit; this avoids deep recursion in its flate dependency.
/// Reject corrupt chunks and bound decompression to 128 MiB.
extern "js" fn png_stored_deflate(data : Bytes) -> Bytes =
  #| (input) => {
  #|   try {
  #|     const zlib = require('node:zlib');
  #|     const data = Buffer.from(input);
  #|     const signature = Buffer.from('89504e470d0a1a0a', 'hex');
  #|     if (data.length < 8 || !data.subarray(0, 8).equals(signature)) return new Uint8Array(0);
  #|     const chunks = [];
  #|     const idats = [];
  #|     let position = 8, firstIdat = -1, afterIdat = false, ended = false;
  #|     while (position + 12 <= data.length) {
  #|       const size = data.readUInt32BE(position);
  #|       const end = position + 12 + size;
  #|       if (end > data.length) return new Uint8Array(0);
  #|       const type = data.toString('ascii', position + 4, position + 8);
  #|       const body = data.subarray(position + 4, position + 8 + size);
  #|       if (zlib.crc32(body) !== data.readUInt32BE(position + 8 + size)) return new Uint8Array(0);
  #|       if (type === 'IDAT') {
  #|         if (afterIdat) return new Uint8Array(0);
  #|         if (firstIdat < 0) { firstIdat = chunks.length; chunks.push(null); }
  #|         idats.push(data.subarray(position + 8, position + 8 + size));
  #|       } else {
  #|         if (firstIdat >= 0) afterIdat = true;
  #|         chunks.push(data.subarray(position, end));
  #|       }
  #|       position = end;
  #|       if (type === 'IEND') { ended = true; break; }
  #|     }
  #|     if (!ended || position !== data.length || firstIdat < 0) return new Uint8Array(0);
  #|     const raw = zlib.inflateSync(Buffer.concat(idats), {maxOutputLength: 128 * 1024 * 1024});
  #|     const packed = zlib.deflateSync(raw, {level: 0});
  #|     const size = Buffer.alloc(4), checksum = Buffer.alloc(4), tag = Buffer.from('IDAT');
  #|     size.writeUInt32BE(packed.length);
  #|     checksum.writeUInt32BE(zlib.crc32(Buffer.concat([tag, packed])));
  #|     chunks[firstIdat] = Buffer.concat([size, tag, packed, checksum]);
  #|     return new Uint8Array(Buffer.concat([signature, ...chunks]));
  #|   } catch (_) { return new Uint8Array(0); }
  #| }

///|
/// Difference hash, average luminance and coarse mean colors.
/// A close hash is only a review hint and never authorizes deletion.
pub fn analyze_image(data : Bytes, extension : String) -> (String, ImageInfo)? {
  let bytes = if extension.to_lower() == ".png" {
    png_stored_deflate(data)
  } else {
    data
  }
  let reader = @io.Buffer::from_bytes(bytes)
  let (image, error) = if extension.to_lower() == ".png" {
    @png.decode(reader)
  } else if extension.to_lower() == ".jpg" || extension.to_lower() == ".jpeg" {
    @jpeg.decode(reader)
  } else {
    return None
  }
  if error is Some(_) {
    return None
  }
  let bounds = image.bounds()
  let width = bounds.dx()
  let height = bounds.dy()
  if width < 1 || height < 1 {
    return None
  }
  let bits = StringBuilder()
  let samples : Array[UInt32] = []
  let mut gray_sum = 0U
  let mut red_sum = 0U
  let mut green_sum = 0U
  let mut blue_sum = 0U
  for row = 0; row < 8; row = row + 1 {
    let y = bounds.min.y + (row * height / 8).min(height - 1)
    let mut previous = 0U
    for col = 0; col < 9; col = col + 1 {
      let x = bounds.min.x + (col * width / 9).min(width - 1)
      let (red, green, blue, _) = image.at(x, y).rgba()
      let gray = (red * 299U + green * 587U + blue * 114U) / 257000U
      if col < 8 {
        samples.push(gray)
        gray_sum = gray_sum + gray
        red_sum = red_sum + red / 257U
        green_sum = green_sum + green / 257U
        blue_sum = blue_sum + blue / 257U
      }
      if col > 0 {
        bits.write_char(if previous > gray { '1' } else { '0' })
      }
      previous = gray
    }
  }
  let average = gray_sum / 64U
  for sample in samples {
    bits.write_char(if sample >= average { '1' } else { '0' })
  }
  for color in [red_sum / 1024U, green_sum / 1024U, blue_sum / 1024U] {
    for level = 0; level < 16; level = level + 1 {
      bits.write_char(
        if level < color.reinterpret_as_int() {
          '1'
        } else {
          '0'
        },
      )
    }
  }
  Some(
    (
      bits.to_string(),
      {
        width,
        height,
        luminance: (gray_sum / 64U).reinterpret_as_int(),
        red: (red_sum / 64U).reinterpret_as_int(),
        green: (green_sum / 64U).reinterpret_as_int(),
        blue: (blue_sum / 64U).reinterpret_as_int(),
      },
    ),
  )
}

///|
/// Build the 176-bit image signature when the input is a supported decodable image.
pub fn fingerprint(data : Bytes, extension : String) -> String? {
  match analyze_image(data, extension) {
    Some((signature, _)) => Some(signature)
    None => None
  }
}
