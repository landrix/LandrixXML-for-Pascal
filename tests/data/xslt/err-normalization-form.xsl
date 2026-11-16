<?xml version="1.0" encoding="UTF-8"?>
<!-- an unknown normalization form is an error when the result is
     serialized (Saxon: also fully-normalized) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output normalization-form="fully-normalized"/>
  <xsl:template match="/"><out/></xsl:template>
</xsl:stylesheet>
