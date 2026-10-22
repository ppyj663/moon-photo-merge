///|
/// Difference hash, average luminance and coarse mean colors.
/// A close hash is only a review hint and never authorizes deletion.
pub fn analyze_image(data : Bytes, extension : String) -> (String, ImageInfo)? {
  let reader = @io.Buffer::from_bytes(data)
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
