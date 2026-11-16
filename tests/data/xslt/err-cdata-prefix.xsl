<?xml version="1.0" encoding="UTF-8"?>
<!-- an undeclared prefix in cdata-section-elements -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output cdata-section-elements="a q:b"/>
  <xsl:template match="/"><out/></xsl:template>
</xsl:stylesheet>
