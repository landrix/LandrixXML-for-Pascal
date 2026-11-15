<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:attribute has no attribute use-attribute-sets. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:attribute-set name="a"/>
  <xsl:template match="/">
    <out>
      <xsl:attribute name="x" use-attribute-sets="a">1</xsl:attribute>
    </out>
  </xsl:template>
</xsl:stylesheet>
