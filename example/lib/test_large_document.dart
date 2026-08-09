import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

/// Utility to generate a very large test document for testing virtualization
class TestDocumentGenerator {
  
  /// Generate a document with the specified number of paragraphs
  static FluentDocument generateLargeDocument({int paragraphCount = 50}) {
    final document = FluentDocument();
    
    for (int i = 0; i < paragraphCount; i++) {
      final paragraph = Paragraph();
      
      if (i % 10 == 0) {
        final headingFragment = Fragment(
          "Paragraph ${i + 1} - Heading Style Content",
          styles: ['bold'],
          fontSize: 18.0,
        );
        paragraph.fragments.add(headingFragment);
      } else if (i % 7 == 0) {
        final italicFragment = Fragment(
          "This is paragraph number ${i + 1} with italic text for testing purposes. "
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
          "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
          styles: ['italic'],
        );
        paragraph.fragments.add(italicFragment);
      } else if (i % 5 == 0) {
        final textFragment = Fragment("This is paragraph ${i + 1} with a ");
        paragraph.fragments.add(textFragment);
        
        final linkFragment = Link(
          url: "https://example.com/page-${i + 1}",
          text: "test link",
        );
        paragraph.fragments.add(linkFragment);
        
        final afterLinkFragment = Fragment(
          " and some more text to make it longer. "
          "This paragraph contains multiple sentences to test the virtualization system "
          "with realistic content that spans multiple lines."
        );
        paragraph.fragments.add(afterLinkFragment);
      } else {
        final length = (i % 3) + 1;
        final text = _generateParagraphText(i + 1, length);
        final fragment = Fragment(text);
        paragraph.fragments.add(fragment);
      }
      
      document.content.nodes.add(paragraph);
      
      if (i % 20 == 0 && i > 0) {
        document.content.nodes.add(HorizontalRule());
      }
      
      if (i % 25 == 0 && i > 0) {
        final image = FluentImage("https://picsum.photos/seed/test$i/600/400.jpg");
        document.content.nodes.add(image);
      }
      
      if (i % 30 == 0 && i > 0) {
        final list = FluentList(listType: 'bullet');
        for (int j = 0; j < 3; j++) {
          final listItem = ListItem(bulletType: 'disc', indexList: [j + 1]);
          final fragment = Fragment("List item ${j + 1} in paragraph $i");
          listItem.fragments.add(fragment);
          list.items.add(listItem);
        }
        document.content.nodes.add(list);
      }
    }
    
    return document;
  }
  
  /// Generate realistic paragraph text
  static String _generateParagraphText(int paragraphNumber, int sentenceCount) {
    final sentences = [
      "This is paragraph number $paragraphNumber with standard text content.",
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
      "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
      "Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium.",
      "Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit.",
      "At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium.",
      "Et harum quidem rerum facilis est et expedita distinctio nam libero tempore cum soluta nobis.",
      "Itaque earum rerum hic tenetur a sapiente delectus ut aut reiciendis voluptatibus maiores alias."
    ];
    
    final buffer = StringBuffer();
    for (int i = 0; i < sentenceCount; i++) {
      final sentenceIndex = (paragraphNumber + i) % sentences.length;
      buffer.write(sentences[sentenceIndex]);
      if (i < sentenceCount - 1) {
        buffer.write(" ");
      }
    }
    
    return buffer.toString();
  }
  
  /// Generate a document with mixed content for comprehensive testing
  static FluentDocument generateMixedContentDocument({int sections = 50}) {
    final document = FluentDocument();
    
    for (int i = 0; i < sections; i++) {
      final headingParagraph = Paragraph();
      final headingFragment = Fragment(
        "Section ${i + 1}",
        styles: ['bold'],
        fontSize: 24.0,
      );
      headingParagraph.fragments.add(headingFragment);
      document.content.nodes.add(headingParagraph);
      
      final subheadingParagraph = Paragraph();
      final subheadingFragment = Fragment(
        "Subtitle for section ${i + 1}",
        styles: ['bold'],
        fontSize: 16.0,
      );
      subheadingParagraph.fragments.add(subheadingFragment);
      document.content.nodes.add(subheadingParagraph);
      
      for (int j = 0; j < 5; j++) {
        final contentParagraph = Paragraph();
        final contentFragment = Fragment(
          "This is content paragraph ${j + 1} in section ${i + 1}. "
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
          "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
          "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."
        );
        contentParagraph.fragments.add(contentFragment);
        document.content.nodes.add(contentParagraph);
      }
      
      if (i % 3 == 0) {
        final list = FluentList(listType: 'bullet');
        for (int j = 0; j < 4; j++) {
          final listItem = ListItem(bulletType: 'disc', indexList: [j + 1]);
          final fragment = Fragment("Bullet point ${j + 1} in section $i");
          listItem.fragments.add(fragment);
          list.items.add(listItem);
        }
        document.content.nodes.add(list);
      }
      
      if (i % 5 == 0) {
        document.content.nodes.add(HorizontalRule());
      }
    }
    
    return document;
  }
}
