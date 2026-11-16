<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE1205: xsl:key with neither use nor a sequence constructor. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:key name="k" match="*"/>
  <xsl:template match="/">
    <out/>
  </xsl:template>
</xsl:stylesheet>
