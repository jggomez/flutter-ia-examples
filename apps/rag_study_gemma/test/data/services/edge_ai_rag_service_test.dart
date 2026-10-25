import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/services/edge_ai_rag_service.dart';

void main() {
  group('EdgeAiRagServiceImpl.hasRepetitionLoop', () {
    test('returns false for normal multi-bullet summary repeating the same citation', () {
      const response = '''
- **Emisor**: Empresa de Energía de Bogotá S.A. E.S.P. [Factura.pdf, p. 1]
- **Periodo facturado**: Del 01 de septiembre al 30 de septiembre de 2026 [Factura.pdf, p. 1]
- **Consumo registrado**: 184 kWh en tarifa residencial estrato 4 [Factura.pdf, p. 1]
- **Fecha límite de pago**: 15 de octubre de 2026 sin recargo por mora [Factura.pdf, p. 1]
- **Total a pagar**: \$142.500 COP incluyendo alumbrado público [Factura.pdf, p. 1]
''';

      expect(EdgeAiRagServiceImpl.hasRepetitionLoop(response), isFalse);
    });

    test('returns true for tandem word/phrase loops (3x consecutive 8..80 chars)', () {
      const loopText =
          'El resumen del documento muestra que repite y repite y repite y repite';

      expect(EdgeAiRagServiceImpl.hasRepetitionLoop(loopText), isTrue);
    });

    test('returns true for 2x consecutive phrase loops (32..120 chars)', () {
      const loopText =
          'El valor total de la factura es de \$150.000 COP. '
          'El valor total de la factura es de \$150.000 COP.';

      expect(EdgeAiRagServiceImpl.hasRepetitionLoop(loopText), isTrue);
    });

    test('returns false when a 48+ char clause appears twice, and true on the 3rd occurrence', () {
      const twiceText =
          '- La factura corresponde al servicio de acueducto y alcantarillado del mes de octubre [Factura.pdf, p. 1]\n'
          '- El pago oportuno debe realizarse antes del día veinte del mes en curso [Factura.pdf, p. 1]\n'
          '- La factura corresponde al servicio de acueducto y alcantarillado del mes de octubre [Factura.pdf, p. 2]';

      expect(EdgeAiRagServiceImpl.hasRepetitionLoop(twiceText), isFalse);

      const thriceText =
          '$twiceText\n'
          '- Otra nota informativa sobre el contrato vigente de servicios públicos [Factura.pdf, p. 2]\n'
          '- La factura corresponde al servicio de acueducto y alcantarillado del mes de octubre [Factura.pdf, p. 3]';

      expect(EdgeAiRagServiceImpl.hasRepetitionLoop(thriceText), isTrue);
    });
  });
}
