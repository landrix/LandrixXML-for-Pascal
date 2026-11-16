<?xml version="1.0" encoding="UTF-8"?>
<!-- default-collation without a known collation: XTSE0125 -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out xsl:default-collation="http://unknown.example/a urn:b"/>
  </xsl:template>
</xsl:stylesheet>
