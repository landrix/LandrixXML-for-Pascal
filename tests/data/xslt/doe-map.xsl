<?xml version="1.0" encoding="UTF-8"?>
<!-- the character map and normalization apply to raw text too; raw text is indented as text -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output use-character-maps="cm" normalization-form="NFC" indent="yes"/>
  <xsl:character-map name="cm"><xsl:output-character character="X" string="[x]"/></xsl:character-map>
  <xsl:template match="/">
    <out><a>X<xsl:value-of select="concat('X&lt;', 'e', codepoints-to-string(769))" disable-output-escaping="yes"/>X</a>
    <b><xsl:text disable-output-escaping="yes">  </xsl:text></b><c/>
    <xsl:text disable-output-escaping="yes">&lt;raw/&gt;</xsl:text>
    <d><xsl:text disable-output-escaping="yes"></xsl:text></d>
    </out>
  </xsl:template>
</xsl:stylesheet>
