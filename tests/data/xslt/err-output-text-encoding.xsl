<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- method text: a character the encoding does not have is an error -->
<xsl:output method="text" encoding="us-ascii"/>
<xsl:template match="/">a&#xE9;</xsl:template>
</xsl:stylesheet>
