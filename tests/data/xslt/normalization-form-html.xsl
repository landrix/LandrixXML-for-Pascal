<?xml version="1.0" encoding="UTF-8"?>
<!-- normalization-form with the html method: text, attribute values (URI
     attributes before %-escaping), script content -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" normalization-form="NFC"/>
  <xsl:template match="/">
    <html><body><p t="éx">é<a href="é.html">l</a></p><script>var s="é";</script><pre>é
é</pre>text é line
two é</body></html>
  </xsl:template>
</xsl:stylesheet>
