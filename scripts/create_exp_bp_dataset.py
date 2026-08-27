#!/usr/bin/env python3
import os
import random
import pydicom
import numpy as np
from PIL import Image
from pydicom.dataset import Dataset, FileDataset
import json
import argparse

def create_folders(base_path, identifier):
    dataset_path = os.path.join(base_path, f"DATASET_{identifier}")
    folders = [
        "METADATA", "IMAGES", "ANNOTATIONS", "LANDING_PAGE/THUMBNAILS", "PRIVATE"
    ]

    for folder in folders:
        os.makedirs(os.path.join(dataset_path, folder), exist_ok=True)
    return dataset_path

def create_xml_files(metadata_path):
    xml_files = {
        "dataset.xml": "Dataset", "policy.xml": "Policy",
        "image.xml": "Images", "annotation.xml": "Annotations",
        "observation.xml": "Observations", "observer.xml": "Observers",
        "sample.xml": "Biological Beings, Cases, Specimens, Blocks and Slides",
        "staining.xml": "Stainings"
    }
    for file, content in xml_files.items():
        with open(os.path.join(metadata_path, file), "w") as f:
            f.write(f"<{content} />\n")

def create_geojson(annotations_path):
    geojson_data = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [random.uniform(-180, 180), random.uniform(-90, 90)]
            },
            "properties": {"name": "Annotation 1"}
        }]
    }
    with open(os.path.join(annotations_path, "annotation.geojson"), "w") as f:
        json.dump(geojson_data, f, indent=4)

def create_dicom_image(image_path, image_id, image_size_mb):
    for i in range(2):  # Ensure at least two images
        filename = os.path.join(image_path, f"IMAGE_{image_id}_{i}")
        os.makedirs(filename, exist_ok=True)

        image_size = (512, 512)
        num_slices = max(1, int((image_size_mb * 1024 * 1024) / (512 * 512)))  # Approximate slices count
        pixel_array = np.random.randint(0, 256, size=image_size, dtype=np.uint8)

        for j in range(num_slices):
            ds = Dataset()
            ds.PatientName = "Test^Patient"
            ds.Rows, ds.Columns = image_size
            ds.PhotometricInterpretation = "MONOCHROME2"
            ds.PixelData = pixel_array.tobytes()

            dcm_file = os.path.join(filename, f"slice_{j}.dcm")
            FileDataset(dcm_file, ds, preamble=b"\0" * 128).save_as(dcm_file)

def create_thumbnails(landing_page_path):
    thumbnail_path = os.path.join(landing_page_path, "THUMBNAILS")
    for i in range(3):
        img = Image.fromarray(np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8))
        img.save(os.path.join(thumbnail_path, f"thumbnail_{i}.jpg"))

def create_private_files(private_path):
    private_files = {
        "rems.xml": "Restricted Metadata",
        "organisation.xml": "Organisation Data",
        "datacite.xml": "<DataCite />"
    }
    for file, content in private_files.items():
        with open(os.path.join(private_path, file), "w") as f:
            f.write(content)

def create_dataset(base_path, identifier, image_size_mb):
    dataset_path = create_folders(base_path, identifier)
    create_xml_files(os.path.join(dataset_path, "METADATA"))
    create_geojson(os.path.join(dataset_path, "ANNOTATIONS"))
    create_dicom_image(os.path.join(dataset_path, "IMAGES"), identifier, image_size_mb)
    create_thumbnails(os.path.join(dataset_path, "LANDING_PAGE"))
    create_private_files(os.path.join(dataset_path, "PRIVATE"))

    print(f"Dataset created at: {dataset_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create a dataset folder structure")
    parser.add_argument("identifier", type=str, help="Dataset identifier")
    parser.add_argument("--image-size", type=int, default=10, help="Size of the image files in MB (default: 10MB)")
    args = parser.parse_args()

    create_dataset("./", args.identifier, args.image_size)

