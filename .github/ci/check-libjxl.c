#include <jxl/cms.h>
#include <jxl/decode.h>
#include <jxl/encode.h>

int main(void)
{
	JxlDecoder *decoder = JxlDecoderCreate(NULL);
	JxlEncoder *encoder = JxlEncoderCreate(NULL);

	if (decoder == NULL || encoder == NULL || JxlGetDefaultCms() == NULL) {
		JxlDecoderDestroy(decoder);
		JxlEncoderDestroy(encoder);
		return 1;
	}

	JxlDecoderDestroy(decoder);
	JxlEncoderDestroy(encoder);
	return 0;
}
