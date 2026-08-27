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
        "METADATA",
        "IMAGES",
        "ANNOTATIONS",
        "LANDING_PAGE/THUMBNAILS",
        "PRIVATE"
    ]

    for folder in folders:
        os.makedirs(os.path.join(dataset_path, folder), exist_ok=True)
    return dataset_path

def create_xml_files(metadata_path, identifier):
    # dataset.xml
    dataset_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<DATASET_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <DATASET alias="{identifier}">
        <TITLE>Dummy Dataset {identifier}</TITLE>
        <SHORT_NAME>{identifier}</SHORT_NAME>
        <DESCRIPTION>Automated test dataset for Big Picture project validation.</DESCRIPTION>
        <VERSION>1.0</VERSION>
        <METADATA_STANDARD>2.0.0</METADATA_STANDARD>
        <ATTRIBUTES xsi:nil="true" />
    </DATASET>
</DATASET_SET>
"""
    with open(os.path.join(metadata_path, "dataset.xml"), "w") as f:
        f.write(dataset_xml)

    # policy.xml
    policy_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<POLICY_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	<POLICY alias="POLICY_{identifier}">
		<DATASET_REF alias="{identifier}"></DATASET_REF>
		<ATTRIBUTES>
			<STRING_ATTRIBUTE>
				<TAG>title</TAG>
				<VALUE>N/A</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>policy_text</TAG>
				<VALUE>N/A</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>type_of_dataset</TAG>
				<VALUE>Non-Clinical / Cryptonimized</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>terms_of_use_version</TAG>
				<VALUE>2026-07-29T14:12:08.862948</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>allowed_geographical_distribution</TAG>
				<VALUE>European Union and EEA countries</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>duration_of_use</TAG>
				<VALUE>Limited to the duration of the purpose of the data access request</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>defined_research_question_required</TAG>
				<VALUE>True</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>type_of_access</TAG>
				<VALUE>Direct access</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>required_bigpicture_acknowledgements</TAG>
				<VALUE>”This project has received funding from the Innovative Medicines Initiative 2 Joint Undertaking under grant agreement No 945358. This Joint Undertaking receives support from the European Union’s Horizon 2020 research and innovation program and EFPIA”</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>legal_basis_for_sharing_the_data</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>informed_consent_form_defined_use_restrictions</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>custom_use_restrictions</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>allowed_uses</TAG>
				<VALUE>
					<STRING_ATTRIBUTE>
						<TAG>allowed_use</TAG>
						<VALUE>Implementation of Bigpicture Project (IMI2-945358)</VALUE>
					</STRING_ATTRIBUTE>
				</VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>required_custom_acknowledgements</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>required_citations</TAG>
				<VALUE>
					<STRING_ATTRIBUTE>
						<TAG>citation</TAG>
						<VALUE>N/A</VALUE>
					</STRING_ATTRIBUTE>
				</VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>licenses</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</SET_ATTRIBUTE>
		</ATTRIBUTES>
	</POLICY>
</POLICY_SET>
"""
    with open(os.path.join(metadata_path, "policy.xml"), "w") as f:
        f.write(policy_xml)

    # sample.xml
    sample_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<SAMPLE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <BIOLOGICAL_BEING alias="being_1">
        <ATTRIBUTES xsi:nil="true" />
    </BIOLOGICAL_BEING>
</SAMPLE_SET>
"""
    with open(os.path.join(metadata_path, "sample.xml"), "w") as f:
        f.write(sample_xml)

    # image.xml
    image_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<IMAGE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <IMAGE alias="image_1">
        <IMAGE_OF alias="being_1" />
        <IMAGE_TYPE>
            <WSI_IMAGE />
        </IMAGE_TYPE>
        <FILES>
            <FILE filename="IMAGE_{identifier}_0/slice_0.dcm" checksum_method="SHA256" checksum="0000000000000000000000000000000000000000000000000000000000000000" filetype="dcm" />
        </FILES>
        <ATTRIBUTES xsi:nil="true" />
    </IMAGE>
</IMAGE_SET>
"""
    with open(os.path.join(metadata_path, "image.xml"), "w") as f:
        f.write(image_xml)

    # annotation.xml
    annotation_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<ANNOTATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <ANNOTATION alias="annotation_1">
        <IMAGE_REF alias="image_1" />
        <FILES>
            <FILE filename="annotation.geojson" checksum_method="SHA256" checksum="0000000000000000000000000000000000000000000000000000000000000000" filetype="json" />
        </FILES>
        <ATTRIBUTES xsi:nil="true" />
    </ANNOTATION>
</ANNOTATION_SET>
"""
    with open(os.path.join(metadata_path, "annotation.xml"), "w") as f:
        f.write(annotation_xml)

    # observer.xml
    observer_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<OBSERVER_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <OBSERVER alias="observer_1">
        <OBSERVER_TYPE>Human</OBSERVER_TYPE>
        <ATTRIBUTES xsi:nil="true" />
    </OBSERVER>
</OBSERVER_SET>
"""
    with open(os.path.join(metadata_path, "observer.xml"), "w") as f:
        f.write(observer_xml)

    # observation.xml
    observation_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<OBSERVATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <OBSERVATION alias="observation_1">
        <IMAGE_REF alias="image_1" />
        <STATEMENT>
            <STATEMENT_TYPE>Finding</STATEMENT_TYPE>
            <STATEMENT_STATUS>Distinct</STATEMENT_STATUS>
            <CODE_ATTRIBUTES xsi:nil="true" />
            <CUSTOM_ATTRIBUTES xsi:nil="true" />
            <FREETEXT>Automated test observation.</FREETEXT>
            <ATTRIBUTES xsi:nil="true" />
        </STATEMENT>
        <ATTRIBUTES xsi:nil="true" />
    </OBSERVATION>
</OBSERVATION_SET>
"""
    with open(os.path.join(metadata_path, "observation.xml"), "w") as f:
        f.write(observation_xml)

    # staining.xml
    staining_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<STAINING_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <STAINING alias="staining_1">
        <PROCEDURE_INFORMATION>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </PROCEDURE_INFORMATION>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </STAINING>
</STAINING_SET>
"""
    with open(os.path.join(metadata_path, "staining.xml"), "w") as f:
        f.write(staining_xml)

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
    for i in range(2):
        filename = os.path.join(image_path, f"IMAGE_{image_id}_{i}")
        os.makedirs(filename, exist_ok=True)

        image_size = (512, 512)
        num_slices = max(1, int((image_size_mb * 1024 * 1024) / (512 * 512)))
        pixel_array = np.random.randint(0, 256, size=image_size, dtype=np.uint8)

        for j in range(num_slices):
            ds = Dataset()
            ds.PatientName = "Test^Patient"
            ds.Rows, ds.Columns = image_size
            ds.PhotometricInterpretation = "MONOCHROME2"
            ds.PixelData = pixel_array.tobytes()

            dcm_file = os.path.join(filename, f"slice_{j}.dcm")
            file_ds = FileDataset(dcm_file, ds, preamble=b"\0" * 128)
            file_ds.save_as(dcm_file)

def create_landing_page(landing_page_path, identifier):
    landing_page_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<LANDING_PAGE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <LANDING_PAGE alias="landing_page_{identifier}">
        <DATASET_REF alias="{identifier}" />
        <SAMPLE_IMAGE_FILES>
            <SAMPLE_IMAGE_FILE filename="THUMBNAILS/thumbnail_0.jpg" checksum_method="SHA256" checksum="0000000000000000000000000000000000000000000000000000000000000000" filetype="jpg" />
        </SAMPLE_IMAGE_FILES>
        <ATTRIBUTES xsi:nil="true" />
    </LANDING_PAGE>
</LANDING_PAGE_SET>
"""
    with open(os.path.join(landing_page_path, "landing_page.xml"), "w") as f:
        f.write(landing_page_xml)

    thumbnail_path = os.path.join(landing_page_path, "THUMBNAILS")
    for i in range(3):
        img = Image.fromarray(np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8))
        img.save(os.path.join(thumbnail_path, f"thumbnail_{i}.jpg"))

def create_private_files(private_path, identifier):
    org_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<ORGANISATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <ORGANISATION alias="org_1">
        <NAME>Test Organization</NAME>
        <PIC_CODE>123456789</PIC_CODE>
        <DATAMANAGER_PERUN_GROUP>perun_group_dummy</DATAMANAGER_PERUN_GROUP>
        <DATASET_REF alias="{identifier}" />
        <ATTRIBUTES xsi:nil="true" />
    </ORGANISATION>
</ORGANISATION_SET>
"""
    with open(os.path.join(private_path, "organisation.xml"), "w") as f:
        f.write(org_xml)

    # Valid rems.xml structure aligned with your example
    rems_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<REMS_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <REMS alias="rems_1">
        <WORKFLOW_ID>1</WORKFLOW_ID>
        <ORGANISATION_ID>nbn</ORGANISATION_ID>
        <DATASET_REF alias="{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </REMS>
</REMS_SET>
"""
    with open(os.path.join(private_path, "rems.xml"), "w") as f:
        f.write(rems_xml)

    with open(os.path.join(private_path, "datacite.xml"), "w") as f:
        f.write("""<?xml version="1.0" encoding="UTF-8"?>\n<DataCite />\n""")

def create_dataset(base_path, identifier, image_size_mb):
    dataset_path = create_folders(base_path, identifier)

    create_xml_files(os.path.join(dataset_path, "METADATA"), identifier)
    create_geojson(os.path.join(dataset_path, "ANNOTATIONS"))
    create_dicom_image(os.path.join(dataset_path, "IMAGES"), identifier, image_size_mb)
    create_landing_page(os.path.join(dataset_path, "LANDING_PAGE"), identifier)
    create_private_files(os.path.join(dataset_path, "PRIVATE"), identifier)

    print(f"Dataset successfully created at: {dataset_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create Big Picture dummy dataset folder structure")
    parser.add_argument("identifier", type=str, help="Dataset identifier")
    parser.add_argument("--image-size", type=int, default=10, help="Size of image files in MB (default: 10MB)")
    args = parser.parse_args()

    create_dataset("./", args.identifier, args.image_size)