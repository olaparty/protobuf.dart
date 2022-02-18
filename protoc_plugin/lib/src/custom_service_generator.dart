// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.11

part of '../protoc.dart';

class CustomServiceGenerator {
  final String serviceName;

  final ServiceDescriptorProto _descriptor;

  /// The generator of the .pb.dart file that will contain this service.
  final FileGenerator fileGen;

  /// The message types needed directly by this service.
  ///
  /// The key is the fully qualified name.
  /// Populated by [resolve].
  final _deps = <String, MessageGenerator>{};

  /// Maps each undefined type to a string describing its location.
  ///
  /// Populated by [resolve].
  final _undefinedDeps = <String, String>{};

  /// Fully-qualified gRPC service name.
  String _fullServiceName;

  /// Dart class name for client stub.
  String _clientClassname;

  /// List of gRPC methods.
  final _methods = <_CustomApiMethod>[];

  CustomServiceGenerator(this._descriptor, this.fileGen) : serviceName = _descriptor.name {
    final name = _descriptor.name;
    final package = fileGen.package;

    if (package != null && package.isNotEmpty) {
      _fullServiceName = '$package.$name';
    } else {
      _fullServiceName = name;
    }

    // avoid: ClientApi
    _clientClassname = name.endsWith('Api') ? name : name + 'Api';
  }

  /// Finds all message types used by this service.
  ///
  /// Puts the types found in [_deps]. If a type name can't be resolved, puts it
  /// in [_undefinedDeps].
  /// Precondition: messages have been registered and resolved.
  void resolve(GenerationContext ctx) {
    for (var method in _descriptor.method) {
      _methods.add(_CustomApiMethod(this, ctx, method));
    }
  }

  /// Adds a dependency on the given message type.
  ///
  /// If the type name can't be resolved, adds it to [_undefinedDeps].
  void _addDependency(GenerationContext ctx, String fqname, String location) {
    if (_deps.containsKey(fqname)) return; // Already added.

    final mg = ctx.getFieldType(fqname) as MessageGenerator;
    if (mg == null) {
      _undefinedDeps[fqname] = location;
      return;
    }
    mg.checkResolved();
    _deps[mg.dottedName] = mg;
  }

  /// Adds dependencies of [generate] to [imports].
  ///
  /// For each .pb.dart file that the generated code needs to import,
  /// add its generator.
  void addImportsTo(Set<FileGenerator> imports) {
    for (var mg in _deps.values) {
      imports.add(mg.fileGen);
    }
  }

  /// Returns the Dart class name to use for a message type.
  ///
  /// Throws an exception if it can't be resolved.
  String _getDartClassName(String fqname) {
    var mg = _deps[fqname];
    if (mg == null) {
      var location = _undefinedDeps[fqname];
      // TODO(nichite): Throw more actionable error.
      throw 'FAILURE: Unknown type reference ($fqname) for $location';
    }
    return mg.fileImportPrefix + mg.classname;
  }

  void generate(IndentingWriter out) {
    out.addBlock('class $_clientClassname {', '}', () {
      out.println();
      for (final method in _methods) {
        method.generateClientStub(out);
      }
    });
  }
}

class _CustomApiMethod {
  final String _dartName;

  final String _argumentType;
  final String _clientReturnType;
  final String _responseType;
  final String _serviceName;

  _CustomApiMethod._(this._serviceName, this._dartName, this._argumentType, this._clientReturnType, this._responseType);

  factory _CustomApiMethod(CustomServiceGenerator service, GenerationContext ctx, MethodDescriptorProto method) {
    final grpcName = method.name;
    final dartName = grpcName; //lowerCaseFirstLetter(grpcName);

    service._addDependency(ctx, method.inputType, 'input type of $grpcName');
    service._addDependency(ctx, method.outputType, 'output type of $grpcName');

    final requestType = service._getDartClassName(method.inputType);
    final responseType = service._getDartClassName(method.outputType);

    final argumentType = requestType;
    final clientReturnType = '$_responseFuture<$responseType?>';

    var serviceName = service.serviceName ?? ''; // upperCaseFirstLetter(service.serviceName);
    // if(serviceName.isNotEmpty){
    //   serviceName = '${serviceName.substring(0, 1).toUpperCase()}${serviceName.substring(1)}';
    // }

    return _CustomApiMethod._(serviceName, dartName, argumentType, clientReturnType, responseType);
  }

  void generateClientStub(IndentingWriter out) {
    out.println();
    out.addBlock('static $_clientReturnType $_dartName($_argumentType request) async {', '}', () {
    out.println("String url = '\${System.domain}$_apiPrefix$_serviceName/$_dartName';");
    out.println("final proto = ProtobufOptions(requestMessage: request, responseMessage: $_responseType());");

    out.println("XhrResponse response = await Xhr.postWithPbOptions(url, proto,throwOnError: false);");
    out.println("if (response.error == null) {");
    out.println("return proto.responseMessage as $_responseType;");
    out.println("}else if(response.error?.code == XhrErrorCode.HttpStatus){");
    out.println("  // TODO: parse http code inline ");
    out.println("  throw response.error;");
    out.println("}");
    out.println("return null;");
    });
  }

  static final String _apiPrefix = 'go/';

  static final String _responseFuture = '${grpcImportPrefix}Future';
}
