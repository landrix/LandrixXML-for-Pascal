<?xml version="1.0" encoding="UTF-8"?>
<!-- copy-namespaces is yes or no -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:copy-of select="." copy-namespaces="maybe"/></out></xsl:template>
</xsl:stylesheet>
