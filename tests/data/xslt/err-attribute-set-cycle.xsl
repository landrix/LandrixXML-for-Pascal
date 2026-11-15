<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0720: an attribute set that uses itself indirectly. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:attribute-set name="a" use-attribute-sets="b"/>
  <xsl:attribute-set name="b" use-attribute-sets="c"/>
  <xsl:attribute-set name="c" use-attribute-sets="a"/>
  <xsl:template match="/">
    <out/>
  </xsl:template>
</xsl:stylesheet>
