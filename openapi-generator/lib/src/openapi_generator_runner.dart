import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:openapi_generator_annotations/openapi_generator_annotations.dart'
    as annots;
import 'package:path/path.dart' as path;
import 'package:source_gen/source_gen.dart';

import 'extensions/type_methods.dart';

class OpenapiGenerator extends GeneratorForAnnotation<annots.Openapi> {
  final Function(String command)? test;

  OpenapiGenerator({this.test});

  @override
  FutureOr<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    try {
      if (element is! ClassElement) {
        final friendlyName = element.displayName;
        throw InvalidGenerationSourceError(
          'Generator cannot target `$friendlyName`.',
          todo: 'Remove the [Openapi] annotation from `$friendlyName`.',
        );
      }
      var separator = '?*?';
      var command = 'generate';

      command = appendInputFileCommandArgs(annotation, command, separator);

      command = appendTemplateDirCommandArgs(annotation, command, separator);

      var generatorName =
          annotation.peek('generatorName')?.enumValue<annots.Generator>();
      var generator = getGeneratorNameFromEnum(generatorName!);
      command = '$command$separator-g$separator$generator';

      var outputDirectory = _readFieldValueAsString(
        annotation,
        'outputDirectory',
        '',
      );
      if (outputDirectory.isNotEmpty) {
        var alwaysRun = _readFieldValueAsBool(annotation, 'alwaysRun', false)!;
        var filePath = path.join(outputDirectory, 'lib/api.dart');
        if (!alwaysRun && await File(filePath).exists()) {
          print(
              'OpenapiGenerator :: Codegen skipped because alwaysRun is set to [$alwaysRun] and $filePath already exists');
          return '';
        }
        command = '$command$separator-o$separator$outputDirectory';
      }

      command = appendTypeMappingCommandArgs(
        annotation,
        command,
        separator,
      );

      command = appendReservedWordsMappingCommandArgs(
        annotation,
        command,
        separator,
      );

      command = appendAdditionalPropertiesCommandArgs(
        annotation,
        command,
        separator,
      );

      command = appendSkipValidateSpecCommandArgs(
        annotation,
        command,
        separator,
      );

      print(
        'OpenapiGenerator :: [${command.replaceAll(separator, ' ')}]',
      );

      var binPath = (await Isolate.resolvePackageUri(
        Uri.parse('package:openapi_generator_cli/openapi-generator.jar'),
      ))!
          .toFilePath(windows: Platform.isWindows);
      test?.call(
        command.replaceAll(separator, ' '),
      );
      // Include java environment variables in command
      var JAVA_OPTS = Platform.environment['JAVA_OPTS'] ?? '';

      var arguments = [
        '-jar',
        "${"$binPath"}",
        ...command.split(separator).toList(),
      ];
      if (JAVA_OPTS.isNotEmpty) {
        arguments.insert(0, JAVA_OPTS);
      }

      var spaced = '|                                                     |';
      var horiborder = '------------------------------------------------------';
      print(
          '$horiborder\n$spaced\n|             Openapi generator for dart              |\n$spaced\n$spaced\n$horiborder');
      print('Executing command [${command.replaceAll(separator, ' ')}]');

      var exitCode = 0;
      var pr = await Process.run('java', arguments);

      print(pr.stderr);
      print(
          'OpenapiGenerator :: Codegen ${pr.exitCode != 0 ? 'Failed' : 'completed successfully'}');
      exitCode = pr.exitCode;

      if (!_readFieldValueAsBool(annotation, 'fetchDependencies')!) {
        print(
            'OpenapiGenerator :: Skipping install step because you said so...');
        return '';
      }

      if (exitCode == 0) {
        final command = _getCommandWithWrapper(
          'flutter',
          ['pub', 'get'],
          annotation,
        );
        var installOutput = await Process.run(
          command.executable,
          command.arguments,
          runInShell: Platform.isWindows,
          workingDirectory: '$outputDirectory',
        );

        print(installOutput.stderr);
        print(
          'OpenapiGenerator :: Install exited with code ${installOutput.exitCode}',
        );
        exitCode = installOutput.exitCode;
      }

      if (!_readFieldValueAsBool(annotation, 'runSourceGenOnOutput')!) {
        print(
            'OpenapiGenerator :: Skipping source gen step because you said so...');
        return '';
      }

      if (exitCode == 0) {
        //run buildrunner to generate files
        switch (generatorName) {
          case annots.Generator.dart:
            print(
                'OpenapiGenerator :: skipping source gen because generator does not need it ::');
            break;
          case annots.Generator.dio:
          case annots.Generator.dioAlt:
            try {
              var runnerOutput = await runSourceGen(
                annotation,
                outputDirectory,
              );
              print(
                  'OpenapiGenerator :: build runner exited with code ${runnerOutput.exitCode} ::');
            } catch (e) {
              print(e);
              print('OpenapiGenerator :: could not complete source gen ::');
            }
            break;
        }
        try {
          var runnerOutput = await runFlutterFormat(
            annotation,
            outputDirectory,
          );
          print('OpenapiGenerator :: Flutter Format exited with code ${runnerOutput.exitCode} ::');
        } catch (e) {
          print(e);
          print('OpenapiGenerator :: could not complete Flutter Format ::');
        }
      }
    } catch (e) {
      print('Error generating spec $e');
      rethrow;
    }
    return '';
  }

  Future<ProcessResult> runSourceGen(
      ConstantReader annotation, String outputDirectory) async {
    print('OpenapiGenerator :: running source code generation ::');
    var c = 'pub run build_runner build --delete-conflicting-outputs';
    final command = _getCommandWithWrapper(
      'flutter',
      c.split(' ').toList(),
      annotation,
    );
    ProcessResult runnerOutput;
    runnerOutput = await Process.run(
      command.executable,
      command.arguments,
      runInShell: Platform.isWindows,
      workingDirectory: '$outputDirectory',
    );
    print(runnerOutput.stderr);
    return runnerOutput;
  }

  Future<ProcessResult> runFlutterFormat(
      ConstantReader annotation, String outputDirectory) async {
    print('OpenapiGenerator :: running Flutter Format ::');
    var c = 'format .';
    final command = _getCommandWithWrapper(
      'flutter',
      c.split(' ').toList(),
      annotation,
    );
    ProcessResult runnerOutput;
    runnerOutput = await Process.run(
      command.executable,
      command.arguments,
      runInShell: Platform.isWindows,
      workingDirectory: '$outputDirectory',
    );
    print(runnerOutput.stderr);
    return runnerOutput;
  }

  String appendAdditionalPropertiesCommandArgs(
    ConstantReader annotation,
    String command,
    String separator,
  ) {
    var additionalProperties = '';
    annotation
        .read('additionalProperties')
        .revive()
        .namedArguments
        .entries
        .forEach(
          (entry) => {
            additionalProperties =
                '$additionalProperties${additionalProperties.isEmpty ? '' : ','}${convertToPropertyKey(entry.key)}=${convertToPropertyValue(entry.value)}'
          },
        );

    if (additionalProperties.isNotEmpty) {
      command =
          '$command$separator--additional-properties=$additionalProperties';
    }

    final serializationLibraryAnnotation =
        annotation.read('serializationLibrary').revive();

    if (serializationLibraryAnnotation.accessor ==
        'SerializationLibrary.json') {
      command +=
          ',serializationLibrary=json_serializable,useEnumExtension=true';
    }

    return command;
  }

  String appendTypeMappingCommandArgs(
      ConstantReader annotation, String command, String separator) {
    var typeMappingsMap = _readFieldValueAsMap(annotation, 'typeMappings', {})!;
    if (typeMappingsMap.isNotEmpty) {
      command =
          '$command$separator--type-mappings=${getMapAsString(typeMappingsMap)}';
    }
    return command;
  }

  String appendImportMappingCommandArgs(
      ConstantReader annotation, String command, String separator) {
    var importMappings =
        _readFieldValueAsMap(annotation, 'importMappings', {})!;
    if (importMappings.isNotEmpty) {
      command =
          '$command$separator--import-mappings=${getMapAsString(importMappings)}';
    }
    return command;
  }

  String appendReservedWordsMappingCommandArgs(
      ConstantReader annotation, String command, String separator) {
    var reservedWordsMappingsMap =
        _readFieldValueAsMap(annotation, 'reservedWordsMappings', {})!;
    if (reservedWordsMappingsMap.isNotEmpty) {
      command =
          '$command$separator--reserved-words-mappings=${getMapAsString(reservedWordsMappingsMap)}';
    }
    return command;
  }

  String getGeneratorNameFromEnum(annots.Generator generator) {
    var genName = 'dart';
    switch (generator) {
      case annots.Generator.dart:
        break;
      case annots.Generator.dio:
        genName = 'dart-dio';
        break;
      case annots.Generator.dioAlt:
        genName = 'dart2-api';
        break;
      default:
        throw InvalidGenerationSourceError(
          'Generator name must be any of ${annots.Generator.values}.',
        );
    }
    return genName;
  }

  String appendTemplateDirCommandArgs(
    ConstantReader annotation,
    String command,
    String separator,
  ) {
    var templateDir = _readFieldValueAsString(
      annotation,
      'templateDirectory',
      '',
    );
    if (templateDir.isNotEmpty) {
      command = '$command$separator-t$separator$templateDir';
    }
    return command;
  }

  String appendInputFileCommandArgs(
      ConstantReader annotation, String command, String separator) {
    var inputFile = _readFieldValueAsString(
      annotation,
      'inputSpecFile',
      '',
    );
    if (inputFile.isNotEmpty) {
      command = '$command$separator-i$separator$inputFile';
    }
    return command;
  }

  String appendSkipValidateSpecCommandArgs(
    ConstantReader annotation,
    String command,
    String separator,
  ) {
    var skipSpecValidation =
        _readFieldValueAsBool(annotation, 'skipSpecValidation', false)!;
    if (skipSpecValidation) {
      command = '$command$separator--skip-validate-spec';
    }
    return command;
  }

  String getMapAsString(Map<dynamic, dynamic> data) {
    return data.entries
        .map((entry) =>
            '${entry.key.toStringValue()}=${entry.value.toStringValue()}')
        .join(',');
  }

  Command _getCommandWithWrapper(
    String command,
    List<String> arguments,
    ConstantReader annotation,
  ) {
    final wrapper = annotation
        .read('additionalProperties')
        .read('wrapper')
        .enumValue<annots.Wrapper>();
    switch (wrapper) {
      case annots.Wrapper.flutterw:
        return Command('./flutterw', arguments);
      case annots.Wrapper.fvm:
        return Command('fvm', [command, ...arguments]);
      case annots.Wrapper.none:
      default:
        return Command(command, arguments);
    }
  }

  String _readFieldValueAsString(
    ConstantReader annotation,
    String fieldName,
    String defaultValue,
  ) {
    var reader = annotation.read(fieldName);

    return reader.isNull ? defaultValue : reader.stringValue;
  }

  Map? _readFieldValueAsMap(
    ConstantReader annotation,
    String fieldName, [
    Map? defaultValue,
  ]) {
    var reader = annotation.read(fieldName);

    return reader.isNull ? defaultValue : reader.mapValue;
  }

  bool? _readFieldValueAsBool(
    ConstantReader annotation,
    String fieldName, [
    bool? defaultValue,
  ]) {
    var reader = annotation.read(fieldName);

    return reader.isNull ? defaultValue : reader.boolValue;
  }

  String convertToPropertyKey(String key) {
    switch (key) {
      case 'nullSafeArrayDefault':
        return 'nullSafe-array-default';
      case 'pubspecDependencies':
        return 'pubspec-dependencies';
      case 'pubspecDevDependencies':
        return 'pubspec-dev-dependencies';
    }
    return key;
  }

  String convertToPropertyValue(DartObject value) {
    if (value.isNull) {
      return '';
    }
    return value.toStringValue() ??
        value.toBoolValue()?.toString() ??
        value.toIntValue()?.toString() ??
        '';
  }
}

class Command {
  final String executable;
  final List<String> arguments;

  Command(this.executable, this.arguments);
}
