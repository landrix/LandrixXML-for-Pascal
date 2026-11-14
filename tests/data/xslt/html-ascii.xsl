<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- HTML in US-ASCII: the meta element names the encoding -->
<xsl:output method="html" encoding="US-ASCII"/>
<xsl:template match="/"><html><head><title>&#xE9;</title></head><body><p title="&#x20AC;&#xA0;">&#xE9;&#x1F600;&#xA0;</p></body></html></xsl:template>
</xsl:stylesheet>
