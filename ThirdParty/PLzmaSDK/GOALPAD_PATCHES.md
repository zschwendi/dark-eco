# GOALPad PLzmaSDK patch record

This directory vendors PLzmaSDK 1.6.1 at upstream commit
`f449bc3e13204b68a7e05fca80ce8c31642085ec` under its MIT license.

GOALPad applies the complete set of upstream 7-Zip 26.01 to 26.02 changes that
intersect the embedded LZMA SDK. The source is taken from official 7-Zip tag
`26.02` at commit `f9d78aff31a5f2521ae7ddbdc97c4a8855808959`.

The app-specific reader is intentionally narrower than general 7z support:

- Copy, LZMA, and LZMA2 are the only accepted coders.
- LZMA/LZMA2 dictionaries are capped at 256 MiB before decoder allocation.
- Packed and decoded 7z headers are capped at 64 MiB before allocation.
- Crypto and TAR support are disabled in the Swift package build.

The app supplies additional entry-count, one-ISO, path, encryption, expansion,
free-space, cancellation, output-size, and atomic-activation checks.
