<?xml version="1.0" encoding="UTF-8"?>
<!-- an unknown collation of xsl:key: XTSE1210 -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:key name="k" match="*" use="name()" collation="http://unknown.example/k"/>
  <xsl:template match="/">
    <out/>
  </xsl:template>
</xsl:stylesheet>
