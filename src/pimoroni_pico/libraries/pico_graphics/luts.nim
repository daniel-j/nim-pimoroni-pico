import std/math, std/bitops, std/algorithm

import ./rgb
export rgb

##
## LUT
##

const rgb332ToRgb565Lut*: array[256, uint16] = [
    0x0000.uint16, 0x0800, 0x1000, 0x1800, 0x0001,
    0x0801, 0x1001, 0x1801, 0x0002, 0x0802, 0x1002, 0x1802, 0x0003, 0x0803, 0x1003,
    0x1803, 0x0004, 0x0804, 0x1004, 0x1804, 0x0005, 0x0805, 0x1005, 0x1805, 0x0006,
    0x0806, 0x1006, 0x1806, 0x0007, 0x0807, 0x1007, 0x1807, 0x0020, 0x0820, 0x1020,
    0x1820, 0x0021, 0x0821, 0x1021, 0x1821, 0x0022, 0x0822, 0x1022, 0x1822, 0x0023,
    0x0823, 0x1023, 0x1823, 0x0024, 0x0824, 0x1024, 0x1824, 0x0025, 0x0825, 0x1025,
    0x1825, 0x0026, 0x0826, 0x1026, 0x1826, 0x0027, 0x0827, 0x1027, 0x1827, 0x0040,
    0x0840, 0x1040, 0x1840, 0x0041, 0x0841, 0x1041, 0x1841, 0x0042, 0x0842, 0x1042,
    0x1842, 0x0043, 0x0843, 0x1043, 0x1843, 0x0044, 0x0844, 0x1044, 0x1844, 0x0045,
    0x0845, 0x1045, 0x1845, 0x0046, 0x0846, 0x1046, 0x1846, 0x0047, 0x0847, 0x1047,
    0x1847, 0x0060, 0x0860, 0x1060, 0x1860, 0x0061, 0x0861, 0x1061, 0x1861, 0x0062,
    0x0862, 0x1062, 0x1862, 0x0063, 0x0863, 0x1063, 0x1863, 0x0064, 0x0864, 0x1064,
    0x1864, 0x0065, 0x0865, 0x1065, 0x1865, 0x0066, 0x0866, 0x1066, 0x1866, 0x0067,
    0x0867, 0x1067, 0x1867, 0x0080, 0x0880, 0x1080, 0x1880, 0x0081, 0x0881, 0x1081,
    0x1881, 0x0082, 0x0882, 0x1082, 0x1882, 0x0083, 0x0883, 0x1083, 0x1883, 0x0084,
    0x0884, 0x1084, 0x1884, 0x0085, 0x0885, 0x1085, 0x1885, 0x0086, 0x0886, 0x1086,
    0x1886, 0x0087, 0x0887, 0x1087, 0x1887, 0x00a0, 0x08a0, 0x10a0, 0x18a0, 0x00a1,
    0x08a1, 0x10a1, 0x18a1, 0x00a2, 0x08a2, 0x10a2, 0x18a2, 0x00a3, 0x08a3, 0x10a3,
    0x18a3, 0x00a4, 0x08a4, 0x10a4, 0x18a4, 0x00a5, 0x08a5, 0x10a5, 0x18a5, 0x00a6,
    0x08a6, 0x10a6, 0x18a6, 0x00a7, 0x08a7, 0x10a7, 0x18a7, 0x00c0, 0x08c0, 0x10c0,
    0x18c0, 0x00c1, 0x08c1, 0x10c1, 0x18c1, 0x00c2, 0x08c2, 0x10c2, 0x18c2, 0x00c3,
    0x08c3, 0x10c3, 0x18c3, 0x00c4, 0x08c4, 0x10c4, 0x18c4, 0x00c5, 0x08c5, 0x10c5,
    0x18c5, 0x00c6, 0x08c6, 0x10c6, 0x18c6, 0x00c7, 0x08c7, 0x10c7, 0x18c7, 0x00e0,
    0x08e0, 0x10e0, 0x18e0, 0x00e1, 0x08e1, 0x10e1, 0x18e1, 0x00e2, 0x08e2, 0x10e2,
    0x18e2, 0x00e3, 0x08e3, 0x10e3, 0x18e3, 0x00e4, 0x08e4, 0x10e4, 0x18e4, 0x00e5,
    0x08e5, 0x10e5, 0x18e5, 0x00e6, 0x08e6, 0x10e6, 0x18e6, 0x00e7, 0x08e7, 0x10e7, 0x18e7]

# Downloaded from http://momentsingraphics.de/BlueNoise.html
const blueNoise16x16*: array[256, uint8] = [uint8 111, 49, 142, 162, 113, 195, 71, 177, 201, 50, 151, 94, 66, 37, 85, 252, 25, 99, 239, 222, 32, 250, 148, 19, 38, 106, 220, 170, 194, 138, 13, 167, 125, 178, 79, 15, 65, 173, 123, 87, 213, 131, 247, 23, 116, 54, 229, 212, 41, 202, 152, 132, 189, 104, 53, 236, 161, 62, 1, 181, 77, 241, 147, 68, 2, 244, 56, 91, 230, 5, 204, 28, 187, 101, 144, 206, 33, 92, 190, 107, 223, 164, 114, 36, 214, 156, 139, 70, 245, 84, 226, 48, 126, 158, 17, 135, 83, 196, 21, 254, 76, 45, 179, 115, 12, 40, 169, 105, 253, 176, 211, 59, 100, 180, 145, 122, 172, 97, 235, 129, 215, 149, 199, 8, 72, 26, 238, 44, 232, 31, 69, 11, 205, 58, 18, 193, 88, 60, 112, 221, 140, 86, 120, 153, 208, 130, 243, 160, 224, 110, 34, 248, 165, 24, 234, 184, 52, 198, 171, 6, 108, 188, 51, 89, 137, 186, 154, 78, 47, 134, 98, 157, 35, 249, 95, 63, 16, 75, 219, 39, 0, 67, 228, 121, 197, 240, 3, 74, 127, 20, 227, 143, 246, 175, 119, 200, 251, 103, 146, 14, 209, 174, 109, 218, 192, 82, 203, 163, 29, 93, 150, 22, 166, 182, 55, 30, 90, 64, 42, 141, 168, 57, 117, 46, 216, 233, 61, 128, 81, 237, 217, 118, 159, 255, 185, 27, 242, 102, 4, 133, 73, 191, 9, 210, 43, 96, 7, 136, 231, 80, 10, 124, 225, 207, 155, 183]
const blueNoise32x32*: array[1024, uint8] = [uint8 153, 167, 218, 245, 148, 195, 210, 228, 140, 242, 35, 59, 253, 146, 111, 9, 248, 121, 57, 95, 78, 190, 231, 61, 114, 18, 66, 105, 144, 192, 95, 73, 251, 87, 57, 177, 121, 76, 23, 110, 66, 162, 214, 119, 90, 44, 218, 65, 137, 166, 21, 226, 46, 214, 127, 40, 242, 153, 179, 82, 5, 212, 17, 124, 36, 111, 16, 44, 234, 7, 172, 131, 191, 83, 9, 175, 133, 230, 189, 33, 178, 235, 195, 147, 117, 28, 164, 140, 91, 200, 32, 219, 238, 135, 62, 185, 146, 224, 208, 138, 98, 155, 217, 40, 250, 29, 152, 238, 16, 74, 160, 100, 82, 1, 105, 70, 255, 176, 83, 8, 223, 51, 126, 161, 113, 44, 170, 231, 25, 190, 80, 64, 199, 244, 88, 57, 118, 98, 201, 52, 108, 205, 25, 126, 211, 53, 133, 204, 14, 58, 237, 191, 109, 67, 252, 22, 75, 204, 88, 104, 130, 2, 170, 115, 28, 181, 12, 145, 168, 224, 71, 182, 141, 248, 60, 226, 151, 246, 184, 37, 157, 99, 208, 145, 19, 169, 97, 196, 150, 10, 244, 53, 71, 250, 150, 229, 49, 124, 74, 235, 209, 2, 128, 36, 94, 6, 171, 117, 43, 19, 87, 112, 222, 74, 121, 45, 181, 132, 233, 41, 138, 178, 220, 158, 201, 93, 38, 214, 101, 163, 198, 24, 106, 47, 160, 232, 193, 147, 75, 197, 96, 161, 233, 175, 137, 4, 243, 30, 225, 78, 0, 212, 63, 107, 32, 120, 235, 59, 184, 9, 143, 248, 61, 134, 189, 81, 253, 63, 113, 29, 222, 242, 11, 65, 213, 25, 54, 198, 166, 149, 90, 55, 188, 122, 240, 84, 193, 17, 168, 111, 132, 82, 21, 206, 91, 33, 175, 152, 18, 215, 177, 87, 51, 130, 186, 142, 121, 80, 249, 104, 67, 216, 114, 246, 154, 96, 13, 164, 49, 142, 209, 29, 220, 233, 173, 45, 112, 239, 223, 120, 96, 136, 11, 206, 157, 34, 103, 204, 45, 155, 187, 37, 128, 10, 195, 20, 173, 37, 131, 225, 255, 76, 43, 101, 154, 68, 122, 192, 158, 4, 71, 54, 196, 42, 246, 70, 119, 173, 254, 6, 229, 92, 15, 236, 177, 83, 139, 48, 222, 205, 66, 183, 92, 3, 196, 247, 182, 52, 16, 251, 80, 146, 211, 22, 236, 166, 106, 149, 231, 21, 79, 61, 167, 219, 143, 109, 207, 58, 252, 102, 75, 144, 22, 110, 156, 125, 64, 144, 8, 89, 138, 217, 39, 103, 179, 125, 78, 186, 2, 57, 216, 94, 197, 113, 129, 27, 70, 43, 159, 226, 27, 167, 116, 190, 243, 53, 215, 172, 27, 116, 227, 198, 107, 169, 60, 202, 232, 34, 142, 93, 201, 132, 39, 179, 141, 48, 184, 247, 200, 124, 8, 90, 187, 129, 3, 228, 35, 86, 12, 234, 97, 78, 163, 34, 240, 23, 131, 87, 7, 163, 253, 64, 26, 240, 161, 12, 232, 211, 0, 81, 99, 176, 242, 151, 68, 42, 203, 94, 176, 150, 135, 203, 187, 56, 210, 123, 69, 185, 221, 154, 117, 48, 214, 107, 224, 118, 86, 71, 104, 153, 36, 162, 217, 50, 19, 111, 213, 237, 159, 60, 119, 72, 245, 40, 130, 20, 254, 151, 46, 98, 13, 247, 73, 188, 20, 176, 148, 50, 189, 250, 126, 61, 239, 115, 134, 65, 195, 143, 84, 12, 136, 251, 17, 217, 106, 157, 222, 178, 86, 5, 235, 171, 139, 56, 206, 101, 137, 79, 11, 207, 31, 172, 15, 199, 91, 186, 26, 255, 221, 35, 171, 53, 105, 182, 31, 193, 51, 1, 67, 102, 141, 190, 110, 79, 197, 30, 164, 233, 40, 245, 160, 95, 134, 220, 42, 144, 228, 9, 76, 155, 93, 125, 189, 226, 77, 207, 126, 165, 84, 239, 169, 30, 204, 58, 219, 39, 229, 118, 89, 1, 127, 198, 55, 230, 66, 109, 79, 165, 55, 209, 175, 46, 106, 3, 246, 24, 153, 44, 95, 230, 147, 116, 43, 247, 123, 21, 160, 133, 14, 180, 145, 216, 69, 113, 183, 6, 152, 192, 243, 27, 100, 117, 137, 236, 203, 163, 60, 114, 138, 241, 8, 62, 23, 212, 77, 92, 148, 236, 73, 104, 253, 63, 47, 241, 168, 28, 85, 254, 123, 17, 213, 131, 183, 249, 38, 16, 69, 216, 88, 180, 219, 72, 173, 200, 136, 182, 227, 192, 7, 49, 174, 211, 84, 152, 191, 18, 99, 208, 139, 38, 177, 49, 90, 68, 1, 154, 85, 191, 127, 148, 33, 14, 194, 103, 37, 249, 108, 13, 128, 162, 218, 112, 188, 32, 4, 205, 108, 130, 232, 155, 62, 225, 103, 159, 237, 201, 229, 59, 171, 221, 48, 99, 252, 132, 52, 161, 124, 86, 157, 56, 100, 35, 64, 136, 89, 243, 122, 168, 38, 77, 52, 185, 23, 203, 74, 135, 32, 116, 145, 97, 30, 112, 234, 167, 199, 80, 231, 0, 223, 209, 26, 239, 73, 199, 250, 24, 156, 227, 56, 140, 218, 249, 7, 93, 120, 244, 5, 194, 174, 45, 15, 185, 208, 75, 5, 20, 63, 118, 149, 184, 68, 47, 143, 178, 230, 119, 170, 10, 105, 181, 70, 15, 97, 194, 174, 146, 213, 165, 108, 58, 252, 81, 225, 127, 245, 158, 141, 180, 212, 41, 244, 25, 96, 115, 193, 6, 41, 149, 54, 207, 81, 41, 200, 237, 159, 114, 31, 67, 42, 83, 18, 151, 215, 100, 165, 65, 50, 91, 120, 238, 85, 107, 170, 139, 206, 254, 166, 85, 215, 94, 241, 142, 224, 115, 129, 26, 82, 55, 234, 221, 134, 240, 187, 123, 28, 140, 4, 194, 36, 202, 24, 220, 54, 31, 196, 10, 76, 59, 19, 133, 181, 29, 69, 188, 13, 164, 255, 179, 150, 205, 125, 11, 169, 98, 51, 227, 72, 180, 238, 110, 135, 251, 72, 147, 162, 129, 89, 228, 122, 156, 223, 109, 202, 3, 128, 102, 34, 62, 92, 47, 0, 102, 183, 77, 197, 22, 158, 202, 88, 39, 210, 156, 14, 172, 101, 2, 186, 210, 248, 46, 174, 33, 241, 50]
const blueNoise32x32Tweaked*: array[1024, uint8] = [uint8 148, 140, 215, 251, 132, 169, 199, 215, 125, 232, 67, 42, 249, 117, 81, 48, 234, 94, 21, 59, 25, 188, 219, 29, 88, 31, 56, 38, 107, 169, 73, 23, 242, 71, 38, 155, 105, 29, 27, 73, 50, 150, 186, 88, 71, 67, 196, 33, 127, 146, 50, 197, 52, 192, 117, 38, 226, 144, 134, 56, 58, 188, 8, 100, 65, 65, 0, 44, 209, 40, 136, 98, 173, 42, 36, 153, 105, 215, 184, 19, 151, 234, 178, 128, 92, 48, 115, 84, 107, 167, 59, 211, 234, 115, 36, 161, 128, 222, 190, 92, 98, 148, 197, 63, 240, 38, 128, 224, 29, 71, 117, 42, 52, 15, 58, 81, 247, 151, 71, 42, 192, 52, 100, 132, 86, 38, 138, 224, 21, 161, 69, 31, 178, 249, 77, 2, 96, 82, 169, 71, 67, 188, 27, 104, 186, 61, 102, 167, 58, 52, 234, 174, 77, 58, 238, 58, 36, 163, 92, 61, 54, 59, 128, 82, 29, 153, 6, 115, 161, 201, 75, 132, 125, 242, 79, 207, 155, 238, 163, 44, 115, 63, 199, 115, 21, 123, 121, 159, 107, 73, 238, 52, 81, 236, 151, 220, 29, 77, 63, 226, 199, 38, 67, 46, 50, 46, 121, 102, 0, 35, 71, 84, 201, 42, 100, 21, 151, 119, 209, 75, 92, 153, 220, 125, 186, 81, 50, 196, 79, 153, 165, 52, 71, 0, 155, 222, 174, 96, 82, 180, 50, 125, 234, 153, 104, 50, 228, 63, 201, 44, 58, 178, 71, 52, 42, 81, 226, 56, 132, 29, 109, 251, 67, 77, 157, 79, 243, 104, 77, 25, 209, 247, 38, 46, 197, 29, 58, 167, 157, 121, 63, 54, 150, 121, 219, 79, 140, 52, 159, 61, 107, 48, 35, 188, 46, 48, 163, 109, 61, 192, 144, 50, 42, 105, 150, 113, 79, 63, 240, 86, 50, 188, 117, 232, 146, 35, 38, 132, 77, 92, 174, 44, 213, 228, 144, 52, 84, 230, 220, 86, 52, 92, 69, 173, 113, 21, 105, 173, 59, 111, 169, 52, 69, 35, 155, 59, 146, 33, 84, 236, 255, 77, 33, 79, 134, 52, 84, 180, 119, 40, 56, 17, 171, 71, 226, 82, 102, 150, 243, 77, 207, 88, 48, 220, 167, 36, 119, 31, 209, 186, 46, 159, 86, 0, 176, 251, 159, 0, 35, 255, 71, 102, 184, 48, 226, 151, 86, 117, 224, 40, 65, 13, 155, 197, 100, 96, 188, 92, 238, 81, 54, 117, 33, 63, 125, 94, 48, 115, 44, 40, 100, 215, 17, 79, 173, 71, 73, 148, 17, 36, 197, 84, 159, 63, 92, 63, 31, 0, 134, 205, 86, 119, 73, 192, 228, 58, 194, 163, 19, 75, 215, 176, 107, 134, 35, 180, 222, 50, 109, 69, 161, 111, 52, 136, 130, 52, 161, 245, 184, 84, 38, 75, 142, 82, 48, 211, 73, 15, 54, 226, 61, 25, 146, 67, 217, 59, 88, 56, 29, 134, 255, 48, 71, 230, 125, 40, 222, 196, 21, 65, 94, 153, 228, 121, 58, 56, 171, 86, 132, 105, 125, 188, 140, 38, 205, 88, 56, 155, 207, 146, 52, 56, 201, 104, 203, 105, 54, 46, 82, 115, 40, 127, 194, 35, 42, 82, 197, 230, 148, 58, 61, 84, 230, 81, 107, 52, 253, 125, 35, 56, 63, 232, 88, 140, 50, 132, 117, 50, 167, 249, 92, 69, 219, 109, 94, 71, 173, 100, 59, 21, 115, 243, 54, 194, 102, 104, 201, 148, 77, 50, 217, 146, 100, 63, 178, 105, 73, 65, 29, 165, 58, 161, 25, 163, 117, 140, 50, 255, 222, 46, 128, 36, 61, 173, 35, 169, 13, 54, 81, 52, 111, 151, 109, 56, 174, 23, 144, 213, 73, 240, 132, 92, 94, 197, 21, 128, 205, 56, 29, 127, 69, 73, 196, 207, 73, 178, 94, 150, 71, 217, 117, 63, 171, 65, 192, 56, 211, 90, 44, 48, 79, 184, 81, 199, 56, 84, 63, 113, 65, 180, 144, 56, 54, 42, 234, 69, 98, 61, 58, 213, 115, 117, 67, 228, 113, 36, 125, 79, 77, 138, 117, 203, 56, 73, 138, 81, 111, 176, 243, 46, 48, 113, 117, 222, 192, 140, 54, 65, 134, 220, 35, 46, 29, 184, 61, 86, 117, 213, 69, 100, 238, 65, 59, 238, 140, 23, 77, 240, 107, 36, 199, 98, 161, 243, 35, 33, 61, 194, 54, 150, 213, 86, 134, 192, 105, 151, 211, 174, 40, 44, 151, 186, 84, 125, 153, 50, 94, 182, 96, 82, 130, 15, 77, 36, 46, 123, 59, 163, 82, 111, 35, 25, 165, 59, 52, 243, 88, 29, 100, 142, 190, 86, 155, 65, 6, 178, 79, 88, 215, 148, 48, 205, 86, 130, 228, 199, 215, 52, 134, 209, 65, 90, 247, 100, 61, 107, 94, 94, 102, 44, 65, 23, 73, 75, 90, 240, 96, 136, 38, 52, 42, 140, 33, 199, 42, 94, 52, 75, 109, 50, 29, 96, 215, 151, 188, 79, 207, 73, 207, 186, 65, 222, 79, 184, 247, 36, 123, 230, 42, 102, 211, 251, 36, 48, 109, 242, 44, 161, 157, 2, 33, 159, 199, 48, 15, 8, 48, 61, 153, 142, 46, 27, 107, 155, 201, 119, 146, 17, 58, 151, 40, 27, 86, 188, 138, 113, 192, 153, 40, 73, 255, 84, 203, 130, 243, 134, 100, 171, 184, 59, 232, 52, 50, 102, 165, 50, 56, 94, 79, 174, 65, 31, 180, 226, 128, 69, 40, 38, 25, 58, 10, 113, 207, 79, 128, 40, 27, 56, 92, 240, 77, 46, 161, 104, 194, 255, 150, 29, 192, 88, 224, 159, 199, 90, 119, 50, 31, 56, 224, 207, 127, 230, 163, 104, 25, 88, 59, 148, 36, 180, 48, 209, 33, 4, 159, 44, 36, 50, 33, 92, 163, 0, 58, 148, 38, 138, 255, 157, 113, 176, 117, 36, 136, 73, 61, 211, 50, 155, 236, 105, 104, 253, 58, 111, 130, 98, 109, 201, 100, 121, 217, 92, 173, 19, 86, 86, 0, 33, 88, 44, 0, 100, 138, 44, 184, 29, 115, 186, 77, 40, 197, 117, 13, 159, 75, 2, 161, 207, 242, 79, 130, 73, 232, 59]


iterator cacheColors*(): tuple[i: int, c: Rgb] =
  for i in 0 ..< 512:
    let r = (i.uint and 0x1c0) shr 1
    let g = (i.uint and 0x38) shl 2
    let b = (i.uint and 0x7) shl 5
    let cacheCol = constructRgb(
      (r or (r shr 3) or (r shr 6)).int16,
      (g or (g shr 3) or (g shr 6)).int16,
      (b or (b shr 3) or (b shr 6)).int16
    )
    yield (i, cacheCol)

proc getDitherCandidates(col: Rgb; palette: openArray[Rgb]; candidates: var array[16, uint8]) =
  var error: Rgb
  for i in 0 ..< candidates.len:
    candidates[i] = (col + error).closest(palette).uint8
    error += (col - palette[candidates[i]])

  # sort by a rough approximation of luminance, this ensures that neighbouring
  # pixels in the dither matrix are at extreme opposites of luminence
  # giving a more balanced output
  let pal = cast[ptr UncheckedArray[Rgb]](palette[0].unsafeAddr) # openArray workaround
  sort(candidates, func (a: uint8; b: uint8): int =
    (pal[a].luminance() > pal[b].luminance()).int
  )

proc generateDitherCache*(cache: var array[512, array[16, uint8]]; palette: openArray[Rgb]) =
  for i, col in cacheColors():
    getDitherCandidates(col, palette, cache[i])

proc generateNearestCache*(cache: var array[512, uint8]; palette: openArray[Rgb]) =
  for i, col in cacheColors():
    cache[i] = col.closest(palette).uint8

proc generateHslCache*(): array[512, Rgb565] =
  for i, col in cacheColors():
    let h = col.r / 255
    let s = col.g / 255
    let l = col.b / 255
    let hslColor = hslToRgb(h, s, l)
    result[i] = hslColor.toRgb565()

const hslCache* = generateHslCache()

# code from https://nelari.us/post/quick_and_dirty_dithering/#bayer-matrix
proc bayerMatrix*[T](M: static[Natural]; mutliplier: float = 1 shl M shl M; offset: float = 0.0): array[1 shl M shl M, T] =
  const length = 1 shl M shl M
  const dim = 1 shl M
  var i = 0
  for y in 0 ..< dim:
    let yc = y
    for x in 0 ..< dim:
      var v = 0
      var mask = M - 1
      let xc = x xor y
      var bit = 0
      while bit < 2 * M:
        v.setMask ((yc shr mask) and 1) shl bit
        inc(bit)
        v.setMask ((xc shr mask) and 1) shl bit
        inc(bit)
        dec(mask)
      result[i] = T(mutliplier * (v / (length - 1) - offset))
      inc(i)

# backwards compatability
const dither16Pattern* = bayerMatrix[uint8](2)

const threshold = 0.5
const gamma = 2.0
const mutliplier = pow(threshold, 1/gamma) * 255

# bayer matrix dither luts
const ditherPattern2x2Rgb* = bayerMatrix[int16](1, mutliplier, 0.5)
const ditherPattern4x4Rgb* = bayerMatrix[int16](2, mutliplier, 0.5)
const ditherPattern8x8Rgb* = bayerMatrix[int16](3, mutliplier, 0.5)
const ditherPattern16x16Rgb* = bayerMatrix[int16](4, mutliplier, 0.5)

# blue noise dither luts
const bnDitherPattern16x16Rgb* = static:
  var arr: array[256, int16]
  for i, c in blueNoise16x16:
    arr[i] = int16 mutliplier * (c.int / 255 - 0.5)
  arr

const bnDitherPattern32x32Rgb* = static:
  var arr: array[1024, int16]
  for i, c in blueNoise32x32:
    arr[i] = int16 mutliplier * (c.int / 255 - 0.5)
  arr
