<?xml version="1.0" encoding="UTF-8"?>
<!-- an unknown collation computed for xsl:sort: XTDE1035 -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out>
      <xsl:perform-sort select="('b', 'a')">
        <xsl:sort select="." collation="{concat('http://unknown.', 'example/c')}"/>
      </xsl:perform-sort>
    </out>
  </xsl:template>
</xsl:stylesheet>
