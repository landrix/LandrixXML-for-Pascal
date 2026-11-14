<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- encodings: names of UTF-8, UTF-16 by its byte order mark, ISO-8859-1;
     a query is no resource -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="unparsed-text('_text-bom.txt', 'UTF8'), unparsed-text('_text-utf16.txt'),
  unparsed-text('_text-latin1.txt', 'iso-8859-1'), unparsed-text-available('_text.txt?x'),
  unparsed-text-available('_text-bad.txt'), unparsed-text-available('_text-utf16.txt')" separator="|"/>
</xsl:template>
</xsl:stylesheet>
