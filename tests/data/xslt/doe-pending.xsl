<?xml version="1.0" encoding="UTF-8"?>
<!-- white space held back by the indentation keeps its escaping: a
     carriage return is a character reference unless it is raw -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output indent="yes"/>
  <xsl:template match="/">
    <out>
      <a><xsl:text>&#13;</xsl:text><xsl:text disable-output-escaping="yes">&lt;p/&gt;</xsl:text></a>
      <b><xsl:text disable-output-escaping="yes">&#13;</xsl:text></b>
      <c><xsl:text disable-output-escaping="yes">&#13;</xsl:text><xsl:text>&#13;</xsl:text></c>
    </out>
  </xsl:template>
</xsl:stylesheet>
