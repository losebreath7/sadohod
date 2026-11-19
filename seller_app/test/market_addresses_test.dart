import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/market_addresses.dart';

void main() {
  test('six approved territories are stable', () {
    expect(marketTerritories, [
      'корпус А', 'корпус Б', 'вещевые ряды',
      'ангар', 'меха и кожа', 'птичий рынок',
    ]);
  });

  test('indoor address defaults to building A', () {
    final a = parseMarketAddress('2B--32');
    expect(a.recognized, isTrue);
    expect(a.territory, 'корпус А');
    expect(a.code, '2В-32');
    expect(a.inferredBuilding, isTrue);
  });

  test('explicit building B is authoritative', () {
    for (final address in ['Б-2А-07', 'Б 2А-07', 'Корпус Б 2А-07']) {
      final result = parseMarketAddress(address);
      expect(result.recognized, isTrue, reason: address);
      expect(result.territory, 'корпус Б', reason: address);
      expect(result.code, 'Б-2А-07', reason: address);
      expect(result.inferredBuilding, isFalse);
    }
  });

  test('indoor digit line and subdivided stalls', () {
    final digital = parseMarketAddress('1-2-18');
    expect(digital.territory, 'корпус А');
    expect(digital.code, '1-2-18');
    final section = parseMarketAddress('2А-23/1Б');
    expect(section.code, '2А-23/1Б');
    expect(section.details, contains('23 — основной павильон'));
    expect(section.details, contains('1Б — секция'));
  });

  test('street, transverse and TC lines remain outside buildings', () {
    expect(parseMarketAddress('27-34').territory, 'вещевые ряды');
    expect(parseMarketAddress('CT7-166').code, 'СТ7-166');
    expect(parseMarketAddress('СТ3-72').territory, 'вещевые ряды');
    expect(parseMarketAddress('ТЦ-104').territory, 'вещевые ряды');
  });

  test('hangar and fur gallery have their own territories', () {
    expect(parseMarketAddress('АН3-15').territory, 'ангар');
    expect(parseMarketAddress('М1-24').territory, 'меха и кожа');
  });

  test('unknown formats do not get invented locations', () {
    final unknown = parseMarketAddress('25/-49');
    expect(unknown.recognized, isFalse);
    expect(unknown.details, contains('не удалось'));
  });

  test('bird market numerical rows require territorial hint', () {
    final result = parseMarketAddress('3-33', territoryHint: 'птичий рынок');
    expect(result.territory, 'птичий рынок');
    expect(result.details, contains('уточнить'));
  });
}
