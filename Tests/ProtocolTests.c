#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aes.h"
#include "crypto/crypto.h"
#include "crypto_openssl.h"
#include "ed25519/sha512.h"
#include "http_request.h"
#include "playfair/playfair.h"
#include "plist/plist.h"

static unsigned int checks;

static void require(int condition, const char *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void from_hex(const char *hex, unsigned char *bytes, size_t length) {
    for (size_t i = 0; i < length; i++) {
        unsigned int byte;
        if (sscanf(hex + 2 * i, "%2x", &byte) != 1) abort();
        bytes[i] = (unsigned char)byte;
    }
}

/* NIST SP 800-38A F.2.1/F.2.2 and F.5.1/F.5.2, AES-128. */
static void test_aes(void) {
    unsigned char key[16], iv[16], nonce[16], plaintext[64], cbc[64], ctr[64], output[64];
    from_hex("2b7e151628aed2a6abf7158809cf4f3c", key, sizeof(key));
    from_hex("000102030405060708090a0b0c0d0e0f", iv, sizeof(iv));
    from_hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", nonce, sizeof(nonce));
    from_hex("6bc1bee22e409f96e93d7e117393172a"
             "ae2d8a571e03ac9c9eb76fac45af8e51"
             "30c81c46a35ce411e5fbc1191a0a52ef"
             "f69f2445df4f9b17ad2b417be66c3710", plaintext, sizeof(plaintext));
    from_hex("7649abac8119b246cee98e9b12e9197d"
             "5086cb9b507219ee95db113a917678b2"
             "73bed6b8e3c1743b7116e69e22229516"
             "3ff1caa1681fac09120eca307586e1a7", cbc, sizeof(cbc));
    from_hex("874d6191b620e3261bef6864990db6ce"
             "9806f66b7970fdff8617187bb9fffdff"
             "5ae4df3edbd5d35e5b4f09020db03eab"
             "1e031dda2fbe03d1792170a0f3009cee", ctr, sizeof(ctr));

    AES_CTX cbc_context;
    AES_set_key(&cbc_context, key, iv, AES_MODE_128);
    AES_cbc_encrypt(&cbc_context, plaintext, output, sizeof(output));
    require(memcmp(output, cbc, sizeof(cbc)) == 0, "axTLS AES CBC encryption NIST vector");
    AES_set_key(&cbc_context, key, iv, AES_MODE_128);
    AES_convert_key(&cbc_context);
    AES_cbc_decrypt(&cbc_context, cbc, output, sizeof(output));
    require(memcmp(output, plaintext, sizeof(plaintext)) == 0, "axTLS AES CBC decryption NIST vector");

    struct AES_ctx ctr_context;
    AES_init_ctx_iv(&ctr_context, key, nonce);
    memcpy(output, plaintext, sizeof(output));
    AES_CTR_xcrypt_buffer(&ctr_context, output, sizeof(output));
    require(memcmp(output, ctr, sizeof(ctr)) == 0, "tiny-AES CTR NIST vector");

    aes_ctx_t *openssl_context = aes_ctr_init(key, nonce);
    /* Network packets can split in the middle of an AES block. */
    aes_ctr_encrypt(openssl_context, plaintext, output, 7);
    aes_ctr_encrypt(openssl_context, plaintext + 7, output + 7, 25);
    aes_ctr_encrypt(openssl_context, plaintext + 32, output + 32, 32);
    require(memcmp(output, ctr, sizeof(ctr)) == 0, "OpenSSL CTR preserves state across packet splits");
    aes_ctr_destroy(openssl_context);
}

/* SHA-512("abc"), FIPS 180-4 known answer. */
static void test_sha512(void) {
    unsigned char expected[64], output[64];
    from_hex("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
             "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", expected, sizeof(expected));
    sha512_context context;
    require(sha512_init(&context) == 0, "SHA-512 initialization");
    require(sha512_update(&context, (const unsigned char *)"a", 1) == 0, "SHA-512 first fragment");
    require(sha512_update(&context, (const unsigned char *)"bc", 2) == 0, "SHA-512 second fragment");
    require(sha512_final(&context, output) == 0, "SHA-512 finalization");
    require(memcmp(output, expected, sizeof(expected)) == 0, "bundled SHA-512 known answer");
    sha_ctx_t *openssl_context = sha_init();
    sha_update(openssl_context, (const unsigned char *)"abc", 3);
    sha_final(openssl_context, output, NULL);
    sha_destroy(openssl_context);
    require(memcmp(output, expected, sizeof(expected)) == 0, "OpenSSL SHA-512 known answer");
}

/* Synthetic, deterministic receiver vector checked against the original
 * vendored PlayFair implementation before removal of its unused sender code.
 * This contains no captured device data or pairing keys. */
static void test_playfair(void) {
    unsigned char message[164], ciphertext[72], output[16], expected[16];
    for (size_t i = 0; i < sizeof(message); i++) message[i] = (unsigned char)(i * 37 + 11);
    message[12] = 0;
    for (size_t i = 0; i < sizeof(ciphertext); i++) ciphertext[i] = (unsigned char)(i * 13 + 7);
    from_hex("084cfd5f6d71f8cd512d856c372053a6", expected, sizeof(expected));
    playfair_decrypt(message, ciphertext, output);
    require(memcmp(output, expected, sizeof(expected)) == 0, "receiver PlayFair regression vector");
}

static void check_plist(plist_t dictionary) {
    require(dictionary && plist_get_node_type(dictionary) == PLIST_DICT, "plist dictionary type");
    char *name = NULL;
    plist_get_string_val(plist_dict_get_item(dictionary, "name"), &name);
    require(name && strcmp(name, "iMirror & <receiver>") == 0, "plist escaped string");
    free(name);
    uint64_t value = 0;
    plist_get_uint_val(plist_dict_get_item(dictionary, "streamConnectionID"), &value);
    require(value == UINT64_C(0xfedcba9876543210), "plist 64-bit connection identity");
    plist_t streams = plist_dict_get_item(dictionary, "streams");
    require(plist_array_get_size(streams) == 2, "plist streams array");
    uint8_t enabled = 0;
    plist_get_bool_val(plist_array_get_item(streams, 0), &enabled);
    require(enabled == 1, "plist boolean");
    const unsigned char expected[] = {0, 1, 2, 255, 0};
    char *data = NULL;
    uint64_t length = 0;
    plist_get_data_val(plist_array_get_item(streams, 1), &data, &length);
    require(length == sizeof(expected) && data && memcmp(data, expected, sizeof(expected)) == 0, "plist binary payload");
    free(data);
}

static void test_plist(void) {
    plist_t dictionary = plist_new_dict();
    plist_dict_set_item(dictionary, "name", plist_new_string("iMirror & <receiver>"));
    plist_dict_set_item(dictionary, "streamConnectionID", plist_new_uint(UINT64_C(0xfedcba9876543210)));
    plist_t streams = plist_new_array();
    plist_array_append_item(streams, plist_new_bool(1));
    const char data[] = {0, 1, 2, (char)255, 0};
    plist_array_append_item(streams, plist_new_data(data, sizeof(data)));
    plist_dict_set_item(dictionary, "streams", streams);
    for (int binary = 0; binary < 2; binary++) {
        char *serialized = NULL;
        uint32_t length = 0;
        if (binary) plist_to_bin(dictionary, &serialized, &length);
        else plist_to_xml(dictionary, &serialized, &length);
        require(serialized && length > 0, "plist serialization");
        plist_t restored = NULL;
        if (binary) plist_from_bin(serialized, length, &restored);
        else plist_from_xml(serialized, length, &restored);
        check_plist(restored);
        plist_free(restored);
        free(serialized);
    }
    plist_free(dictionary);
}

static void test_http(void) {
    const char request[] = "POST /pair-setup HTTP/1.1\r\nCSeq: 42\r\nContent-Length: 5\r\n\r\nhello";
    http_request_t *parser = http_request_init();
    require(parser != NULL, "HTTP parser initialization");
    /* Force URL, header and body callbacks to span multiple TCP reads. */
    for (size_t i = 0; i < sizeof(request) - 1; i++) {
        require(http_request_add_data(parser, request + i, 1) == 0, "fragmented HTTP request");
        if (i < sizeof(request) - 2) require(!http_request_is_complete(parser), "HTTP request waits for complete body");
    }
    require(http_request_is_complete(parser), "HTTP request complete");
    require(strcmp(http_request_get_method(parser), "POST") == 0, "HTTP method");
    require(strcmp(http_request_get_url(parser), "/pair-setup") == 0, "HTTP URL");
    require(strcmp(http_request_get_header(parser, "CSeq"), "42") == 0, "HTTP header");
    int length = 0;
    const char *body = http_request_get_data(parser, &length);
    require(length == 5 && memcmp(body, "hello", 5) == 0, "HTTP body");
    http_request_destroy(parser);

    parser = http_request_init();
    const char malformed[] = "INVALID / HTTP/1.1\r\n\r\n";
    require(http_request_add_data(parser, malformed, sizeof(malformed) - 1) != 0, "malformed HTTP method rejected");
    require(http_request_has_error(parser), "HTTP parse error reported");
    http_request_destroy(parser);
}

int main(void) {
    test_aes();
    test_sha512();
    test_playfair();
    test_plist();
    test_http();
    printf("PASS: protocol AES, SHA-512, PlayFair, XML/binary plist and fragmented HTTP (%u checks)\n", checks);
    return 0;
}
