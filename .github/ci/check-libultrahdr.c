#include <ultrahdr_api.h>

#include <stdio.h>

int main(void)
{
	uhdr_codec_private_t *encoder = uhdr_create_encoder();
	uhdr_codec_private_t *decoder = uhdr_create_decoder();

	if (encoder == NULL || decoder == NULL) {
		fprintf(stderr, "failed to create UltraHDR codec contexts\n");
		if (encoder != NULL) {
			uhdr_release_encoder(encoder);
		}
		if (decoder != NULL) {
			uhdr_release_decoder(decoder);
		}
		return 1;
	}

	uhdr_release_encoder(encoder);
	uhdr_release_decoder(decoder);
	printf("libultrahdr %s: encoder and decoder are available\n",
		   UHDR_LIB_VERSION_STR);
	return 0;
}
