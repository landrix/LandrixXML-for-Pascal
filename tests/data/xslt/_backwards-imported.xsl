<?xml version="1.0" encoding="UTF-8"?>
<!-- An XSLT 2.0 module imported by backwards.xsl (an XSLT 1.0 stylesheet). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:key name="k" match="item" use="number(.)"/>
  <xsl:template name="two">
    <two><xsl:value-of select="//x"/>|<xsl:value-of select="count(key('k', 1))"/></two>
  </xsl:template>
</xsl:stylesheet>
