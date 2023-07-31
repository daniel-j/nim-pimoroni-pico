const bitmapBaseChars = 96 # 96 printable ASCII chars
const bitmapExtraChars = 9 # Extra chars we've rempped that aren't just an ASCII char plus an accent

type
  BitmapFont* {.byref.} = object
    height*: uint8
    maxWidth*: uint8
    widths*: array[bitmapBaseChars + bitmapExtraChars, uint8]
    data*: UncheckedArray[uint8]

  BitmapRectFunc* = proc(x, y, w, h: int32)

proc measureCharacter*(font: BitmapFont; c: char; scale: uint8; fixedWidth: bool = false): int32 =
  if c.int < 32 or c.int > 127 + 64: # + 64 char remappings defined in unicode_sorta.hpp
    return 0

  if fixedWidth:
    return font.maxWidth.int32 * scale.int32

  var charIndex = c.uint8

  # if(charIndex > 127) {
  #   if(codepage == unicode_sorta::PAGE_195) {
  #     charIndex = unicode_sorta::char_base_195[c - 128];
  #   } else {
  #     charIndex = unicode_sorta::char_base_194[c - 128 - 32];
  #   }
  # }

  charIndex -= 32

  return font.widths[charIndex].int32 * scale.int32

proc measureText*(font: BitmapFont; t: string; scale: uint8 = 2; letterSpacing: uint8 = 1; fixedWidth: bool = false): int32 =
  # unicode_sorta::codepage_t codepage = unicode_sorta::PAGE_195;
  for  c in t:
    # if(c == unicode_sorta::PAGE_194_START) {
    #   codepage = unicode_sorta::PAGE_194;
    #   continue;
    # } else if (c == unicode_sorta::PAGE_195_START) {
    #   continue;
    # }
    result += font.measureCharacter(c, scale, fixedWidth)
    result += letterSpacing.int32 * scale.int32
    # codepage = unicode_sorta::PAGE_195; // Reset back to default

proc character*(font: BitmapFont; rectangle: BitmapRectFunc; c: char; x, y: int32; scale: uint8 = 2) =
  if c.int < 32 or c.int > 127 + 64: # + 64 char remappings defined in unicode_sorta.hpp
    return

  var charIndex = c.uint8
  let charAccent = 0
  # unicode_sorta::accents char_accent = unicode_sorta::ACCENT_NONE;

  # Remap any chars that fall outside of the 7-bit ASCII range
  # using our unicode fudge lookup table.
  # if(charIndex > 127) {
  #   if(codepage == unicode_sorta::PAGE_195) {
  #     charIndex = unicode_sorta::char_base_195[c - 128];
  #     char_accent = unicode_sorta::char_accent[c - 128];
  #   } else {
  #     charIndex = unicode_sorta::char_base_194[c - 128 - 32];
  #     char_accent = unicode_sorta::ACCENT_NONE;
  #   }
  # }

  # We don't map font data for the first 32 non-printable ASCII chars
  charIndex -= 32

  # If our font is taller than 8 pixels it must be two bytes per column
  let twoBytesPerColumn = font.height > 8

  # Figure out how many bytes we need to skip per char to find our data in the array
  let bytesPerChar = if twoBytesPerColumn: font.maxWidth * 2 else: font.maxWidth

  # Get a pointer to the start of the data for this character
  let d = font.data[charIndex * bytesPerChar].unsafeAddr

  # Accents can be up to 8 pixels tall on both 8bit and 16bit fonts
  # Each accent's data is font->max_width bytes + 2 offset bytes long
  let a = font.data[(bitmapBaseChars + bitmapExtraChars) * bytesPerChar.int + charAccent * (font.maxWidth.int + 2)].unsafeAddr

  # Effectively shift off the first two bytes of accent data-
  # these are the lower and uppercase accent offsets
  const uint8_t offset_lower = *a++;
  const uint8_t offset_upper = *a++;

  // Pick which offset we should use based on the case of the char
  // This is only valid for A-Z a-z.
  // Note this magic number is relative to the start of printable ASCII chars.
  uint8_t accent_offset = charIndex < 65 ? offset_upper : offset_lower;

  // Offset our y position to account for our column canvas being 32 pixels
  int y_offset = y - (8 * scale);

  // Iterate through each horizontal column of font (and accent) data
  for(uint8_t cx = 0; cx < font->widths[charIndex]; cx++) {
    // Our maximum bitmap font height will be 16 pixels
    // give ourselves a 32 pixel high canvas in which to plot the char and accent.
    // We shift the char down 8 pixels to make room for an accent above.
    uint32_t data = *d << 8;

    // For fonts that are taller than 8 pixels (up to 16) they need two bytes
    if(two_bytes_per_column) {
      d++;
      data <<= 8;      // Move down the first byte
      data |= *d << 8; // Add the second byte
    }

    // If the char has an accent, merge it into the column data at its offset
    if(char_accent != unicode_sorta::ACCENT_NONE) {
      data |= *a << accent_offset;
    }

    // Draw the 32 pixel column
    for(uint8_t cy = 0; cy < 32; cy++) {
      if((1U << cy) & data) {
        rectangle(x + (cx * scale), y_offset + (cy * scale), scale, scale);
      }
    }

    // Move to the next columns of char and accent data
    d++;
    a++;
  }

proc text*(font: BitmapFont; rectangle: BitmapRectFunc; x, y: int32; wrap: int32; scale: uint8 = 2; letterSpacing: uint8 = 1; fixedWidth: bool = false) =
  discard

