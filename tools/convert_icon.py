import os
import sys
from PIL import Image, ImageFilter

def get_clean_crop_box(img, threshold=240, min_pixels=2, padding_pct=0.05):
    w, h = img.size
    col_dark = [sum(1 for y in range(h) if img.getpixel((x, y)) < threshold) for x in range(w)]
    row_dark = [sum(1 for x in range(w) if img.getpixel((x, y)) < threshold) for y in range(h)]
    
    x_start = next((i for i, val in enumerate(col_dark) if val > min_pixels), 0)
    x_end = next((w - i for i, val in enumerate(reversed(col_dark)) if val > min_pixels), w)
    y_start = next((i for i, val in enumerate(row_dark) if val > min_pixels), 0)
    y_end = next((h - i for i, val in enumerate(reversed(row_dark)) if val > min_pixels), h)
    
    width = x_end - x_start
    height = y_end - y_start
    
    cx = (x_start + x_end) / 2
    cy = (y_start + y_end) / 2
    
    size = max(width, height)
    padded_size = size * (1 + 2 * padding_pct)
    
    crop_x1 = max(0, int(cx - padded_size / 2))
    crop_y1 = max(0, int(cy - padded_size / 2))
    crop_x2 = min(w, int(crop_x1 + padded_size))
    crop_y2 = min(h, int(crop_y1 + padded_size))
    
    actual_w = crop_x2 - crop_x1
    actual_h = crop_y2 - crop_y1
    square_size = min(actual_w, actual_h)
    
    crop_x1 = max(0, int(cx - square_size / 2))
    crop_y1 = max(0, int(cy - square_size / 2))
    crop_x2 = crop_x1 + square_size
    crop_y2 = crop_y1 + square_size
    
    return (crop_x1, crop_y1, crop_x2, crop_y2)

def convert_image(input_path, output_dir, project_root, thickness_boost=15):
    if not os.path.exists(input_path):
        print(f"Error: Input file {input_path} does not exist.")
        sys.exit(1)
        
    os.makedirs(output_dir, exist_ok=True)
    
    # Load the source image and convert to grayscale
    img_gray = Image.open(input_path).convert("L")
    
    # Find bounding box and crop to square with 5% padding
    crop_box = get_clean_crop_box(img_gray, threshold=240, min_pixels=2, padding_pct=0.05)
    cropped_gray = img_gray.crop(crop_box)
    
    # Apply MinFilter to thicken black lines on white background
    if thickness_boost > 1:
        # MinFilter size must be an odd integer >= 3
        # E.g., thickness_boost of 15 means we look at a 15x15 neighborhood
        # and take the minimum (darkest) pixel, expanding black areas by ~7 pixels on all sides.
        cropped_gray = cropped_gray.filter(ImageFilter.MinFilter(thickness_boost))
        print(f"Applied MinFilter with size {thickness_boost} to thicken lines.")
    
    # Create the high-resolution transparent version
    w, h = cropped_gray.size
    rgba_highres = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gray_pixels_hr = cropped_gray.load()
    rgba_pixels_hr = rgba_highres.load()
    
    for y in range(h):
        for x in range(w):
            gray_val = gray_pixels_hr[x, y]
            alpha = 255 - gray_val
            if alpha < 15:
                alpha = 0
            elif alpha > 240:
                alpha = 255
            rgba_pixels_hr[x, y] = (0, 0, 0, alpha)
            
    highres_path = os.path.join(project_root, "StatusBarIconSource.png")
    rgba_highres.save(highres_path, "PNG")
    print(f"Generated high-resolution cropped source with thicker lines: {highres_path}")
    
    # Target sizes for the status bar icon
    sizes = [
        (18, "StatusBarIcon.png"),
        (36, "StatusBarIcon@2x.png")
    ]
    
    for size, filename in sizes:
        # Resize using Lanczos (high quality antialiasing)
        resized_img = cropped_gray.resize((size, size), Image.Resampling.LANCZOS)
        rgba_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gray_pixels = resized_img.load()
        rgba_pixels = rgba_img.load()
        
        for y in range(size):
            for x in range(size):
                gray_val = gray_pixels[x, y]
                alpha = 255 - gray_val
                if alpha < 15:
                    alpha = 0
                elif alpha > 240:
                    alpha = 255
                rgba_pixels[x, y] = (0, 0, 0, alpha)
                
        out_path = os.path.join(output_dir, filename)
        rgba_img.save(out_path, "PNG")
        print(f"Generated {out_path} ({size}x{size})")

if __name__ == "__main__":
    input_img = "/Users/allanpscheidt/.gemini/antigravity/brain/840c53ef-56e1-4a77-9ca4-f28ef99df7d3/menu_bar_icon_1783378883673.jpg"
    project_root = "/Users/allanpscheidt/Documents/_Antigravity/apps/StickIE"
    output_dir = os.path.join(project_root, "build/AppIcon.iconset")
    # Using thickness_boost=15 (which is about 7px expansion on each side in high-res)
    convert_image(input_img, output_dir, project_root, thickness_boost=15)
