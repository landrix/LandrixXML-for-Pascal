<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0430: two namespace nodes binding one prefix to different URIs. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out xmlns:p="urn:a"><xsl:namespace name="p">urn:b</xsl:namespace></out>
  </xsl:template>
</xsl:stylesheet>
