<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- include-content-type (the default): a meta element for the content
     type as the first child of head, the ones there before dropped; no
     indentation (indent="no") -->
<xsl:output method="html" indent="no" media-type="text/x-test"/>
<xsl:template match="/">
<html><head><meta charset="ISO-8859-1"/><meta http-equiv="content-type" content="x"/><title>t</title></head><body><p>a</p><p>b</p></body></html>
</xsl:template>
</xsl:stylesheet>
