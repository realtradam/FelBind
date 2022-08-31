void InitWindow(int width, int height, const char *title);

typedef struct Rectangle {
    float height;           // Rectangle height
} Rectangle;

typedef struct Texture {
    unsigned int id;        // OpenGL texture id
    int format;             // Data format (PixelFormat type)
} Texture;

typedef Texture Texture2D;
