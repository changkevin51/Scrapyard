import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/domain/services/simple_arithmetic.dart';

void main() {
  test('PEMDAS and implicit multiply', () {
    expect(tryEvaluateArithmetic('2+2')!.display, '4');
    expect(tryEvaluateArithmetic('10/2')!.display, '5');
    expect(tryEvaluateArithmetic('2(3+1)')!.display, '8');
    expect(tryEvaluateArithmetic('2*3')!.display, '6');
    expect(tryEvaluateArithmetic('3^2')!.display, '9');
    expect(tryEvaluateArithmetic('2+3*4')!.display, '14');
    expect(tryEvaluateArithmetic('-4+1')!.display, '-3');
    expect(tryEvaluateArithmetic('sqrt(9)')!.display, '3');
    expect(tryEvaluateArithmetic('2sqrt(4)')!.display, '4');
    expect(tryEvaluateArithmetic('((33)/(4))3')!.display, '99/4');
    expect(tryEvaluateArithmetic('(1/2)(1/3)')!.display, '1/6');
  });

  test('subtraction evaluates', () {
    expect(tryEvaluateArithmetic('2-2')!.display, '0');
    expect(tryEvaluateArithmetic('30-2')!.display, '28');
  });

  test('unary minus after exponent', () {
    expect(tryEvaluateArithmetic('3^-2')!.display, '1/9');
    expect(tryEvaluateArithmetic('3^-2')!.answerLatex, r'\frac{1}{9}');
  });

  test('rejects junk, letters, and div-by-zero', () {
    expect(tryEvaluateArithmetic(''), isNull);
    expect(tryEvaluateArithmetic('2+x'), isNull);
    expect(tryEvaluateArithmetic('hello'), isNull);
    expect(tryEvaluateArithmetic('1/0'), isNull);
    expect(tryEvaluateArithmetic('2+'), isNull);
    expect(tryEvaluateArithmetic('(2+3'), isNull);
    expect(tryEvaluateArithmetic('2++2'), isNull);
  });

  test('latex pretty-print', () {
    final r = tryEvaluateArithmetic('2*3^2')!;
    expect(r.latex.contains(r'\times'), isTrue);
    expect(r.latex.contains('^{2}'), isTrue);
  });

  test('MathReader latex converts to arithmetic', () {
    expect(latexToArithmetic(r'2+2'), '2+2');
    expect(latexToArithmetic(r'$2+2$'), '2+2');
    expect(latexToArithmetic(r'2\times 3'), '2*3');
    expect(latexToArithmetic('2x6'), '2*6');
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'2^{x}6')!)!.display,
      '12',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic('2x6')!)!.latex.contains(r'\times'),
      isTrue,
    );
    expect(latexToArithmetic(r'6\div 2'), '6/2');
    expect(latexToArithmetic(r'3\cdot 4'), '3*4');
    expect(latexToArithmetic(r'\frac{1}{2}'), '((1)/(2))');
    expect(tryEvaluateArithmetic(latexToArithmetic(r'2\times 3')!)!.display, '6');
    expect(tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}')!)!.display, '0.5');
    expect(latexToArithmetic(r'\sqrt{4}'), 'sqrt(4)');
    expect(correctRecognizedLatex(r'z+3'), '2+3');
    expect(latexToArithmetic(r'z+z'), '2+2');
    expect(tryEvaluateArithmetic(latexToArithmetic(r'z+3')!)!.display, '5');
    expect(
      tryEvaluateArithmetic(
        latexToArithmetic(r'\frac{33}{4}x3-2=\frac{z3}{4}xz-z')!,
      )!.display,
      '91/4',
    );
    expect(latexToArithmetic(r'\frac{33}{4}3'), '((33)/(4))*3');
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{33}{4}3')!)!.display,
      '99/4',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}(3+1)')!)!.display,
      '2',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}\frac{1}{3}')!)!.display,
      '1/6',
    );
    expect(tryEvaluateArithmetic(latexToArithmetic(r'\sqrt{4}')!)!.display, '2');
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\sqrt{\frac{4}{9}}')!)!.display,
      '2/3',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}+\frac{1}{3}')!)!.display,
      '5/6',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}+\frac{1}{3}')!)!.answerLatex,
      r'\frac{5}{6}',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}+\frac{1}{3}')!)!.decimalDisplay,
      '0.83333333',
    );
    expect(
      tryEvaluateArithmetic(latexToArithmetic(r'\frac{1}{2}+\frac{1}{3}')!)!.displaysAsFraction,
      isTrue,
    );
    expect(tryEvaluateArithmetic('2+2')!.displaysAsFraction, isFalse);
    expect(latexToArithmetic(''), isNull);
  });
}
