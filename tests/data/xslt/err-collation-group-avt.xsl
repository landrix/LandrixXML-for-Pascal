<?xml version="1.0" encoding="UTF-8"?>
<!-- an unknown collation computed for xsl:for-each-group: XTDE1110 -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out>
      <xsl:for-each-group select="('a', 'b')" group-by="." collation="{concat('urn:', 'none')}">
        <g/>
      </xsl:for-each-group>
    </out>
  </xsl:template>
</xsl:stylesheet>
