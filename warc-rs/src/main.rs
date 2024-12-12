//rust program that reads gzipped warc files.
//1. Iterates over each entry within the file
//2. Extracts the links within the content of each entry
//3. Writes the links to a file
//4. Counts the number of links
//5. Prints the number of links

use flate2::read::GzDecoder;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use warc::WarcReader;

fn main() {
    let pstr = "../data/CC-MAIN-20241015204737-20241015234737-00610.warc.gz";
    //let path = Path::new();
    //let file = File::open(path).unwrap();
    //let decoder = GzDecoder::new(file);
    //let reader = BufReader::new(decoder);
    //let warc_reader = WarcReader::new(reader);

    let mut links: Vec<String> = Vec::new();

    use warc::WarcHeader;
    use warc::WarcReader;

    macro_rules! usage_err {
        ($str:expr) => {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, $str.to_string())
        };
    }

    //let mut file = WarcReader::from_path_gzip(warc_name)?;

    let mut count = 0;
    let mut skipped = 0;
    let mut file = WarcReader::from_path_gzip(pstr).unwrap();
    let mut stream_iter = file.stream_records();

    let mut count = 0;

    while let Some(record) = stream_iter.next_item() {
        count += 1;
        //extract the content of the record
        let rec = record.unwrap();
        let buf = rec.into_buffered().unwrap();
        let body = buf.body();
        //convert body to string
        let content_result = String::from_utf8_lossy(body);
        //convert content_result into &str and call extract_links
        let content = content_result.as_ref();
        println!("content: {}", content);
        let links2 = extract_links(content);
        //add links to links
        links.extend(links2);
        if count >= 3 {
            break;
        };
    }
    //print links
    for link in links {
        println!("Links: \n{}", link);
    }
}

fn extract_links(content: &str) -> Vec<String> {
    let mut links = Vec::new();
    let mut start = 0;
    while let Some(href_start) = content[start..].find("href=\"") {
        let href_start = start + href_start + 6;
        match content[href_start..].find("\"") {
            Some(end) => {
                let href_end = href_start + end;
                let link = content[href_start..href_end].to_string();
                links.push(link);
                start = href_end + 1;
            }
            None => break,
        }
    }
    links
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_links() {
        let html = r#"<a href="http://example.com">Link</a>
                     <a href="https://test.com">Another</a>
                     <div href="invalid">Not a link</div>"#;

        let links = extract_links(html);

        assert_eq!(links.len(), 2);
        assert_eq!(links[0], "http://example.com");
        assert_eq!(links[1], "https://test.com");
    }
}
