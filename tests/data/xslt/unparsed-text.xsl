<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- unparsed-text() relative to the module (a byte order mark dropped),
     unparsed-text-available() -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="concat('[', unparsed-text('_text.txt'), ']'), concat('[', unparsed-text('_text-bom.txt', 'UTF-8'), ']'),
  unparsed-text-available('_text.txt'), unparsed-text-available('_none.txt'), unparsed-text-available('_text.txt#x')"
  separator="|"/>
</xsl:template>
</xsl:stylesheet>
