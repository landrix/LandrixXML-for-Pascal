<?xml version="1.0" encoding="UTF-8"?>
<!-- normalization-form NFKD with the text method -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" normalization-form="NFKD"/>
  <xsl:template match="/">ﬁ Å ①</xsl:template>
</xsl:stylesheet>
