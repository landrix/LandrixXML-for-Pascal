<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0710: use-attribute-sets with a name that is not a QName. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:attribute-set name="a"/>
  <xsl:template match="/">
    <xsl:element name="out" use-attribute-sets="a 1b"/>
  </xsl:template>
</xsl:stylesheet>
