<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an encoding given: no byte order mark detection except for UTF-16,
     a leading U+FEFF dropped; the name is not trimmed; no backslash in a URI -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="string-to-codepoints(unparsed-text('_text-bom.txt', 'ISO-8859-1'))"/>|<xsl:value-of
  select="string-to-codepoints(unparsed-text('_text-bom.txt', 'utf-8'))"/>|<xsl:value-of
  select="string-to-codepoints(unparsed-text('_text-utf16.txt', 'utf-16'))"/>|<xsl:value-of
  select="string-to-codepoints(unparsed-text('_text-utf16.txt', 'UTF-16LE'))"/>|<xsl:value-of
  select="unparsed-text-available('_text.txt', ' utf-8 '), unparsed-text-available('_text-utf16.txt', 'utf-16be'),
  unparsed-text-available('_text-bad.txt', 'utf-8'), unparsed-text-available('_text.txt', 'Latin1'),
  unparsed-text-available('_text.txt '), unparsed-text-available('_text-nul.txt'),
  unparsed-text-available('_text-nul.txt', 'utf-8'), unparsed-text-available('sub\..\_text.txt')"/>
</xsl:template>
</xsl:stylesheet>
