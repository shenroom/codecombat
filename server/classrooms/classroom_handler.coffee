async = require 'async'
mongoose = require 'mongoose'
Handler = require '../commons/Handler'
Classroom = require './Classroom'
User = require '../users/User'
sendwithus = require '../sendwithus'

ClassroomHandler = class ClassroomHandler extends Handler
  modelClass: Classroom
  jsonSchema: require '../../app/schemas/models/classroom.schema'
  allowedMethods: ['GET', 'POST', 'PUT', 'DELETE']

  hasAccess: (req) ->
    return false unless req.user
    return true if req.method is 'GET'
    req.method in @allowedMethods or req.user?.isAdmin()

  hasAccessToDocument: (req, document, method=null) ->
    return false unless document?
    return true if req.user?.isAdmin()
    return true if document.get('ownerID')?.equals req.user?._id
    isGet = (method or req.method).toLowerCase() is 'get'
    isMember = _.any(document.get('members') or [], (memberID) -> memberID.equals(req.user.get('_id')))
    return true if isGet and isMember
    false

  makeNewInstance: (req) ->
    instance = super(req)
    instance.set 'ownerID', req.user._id
    instance.set 'members', []
    instance

  getByRelationship: (req, res, args...) ->
    method = req.method.toLowerCase()
    return @inviteStudents(req, res, args[0]) if args[1] is 'invite-members'
    return @joinClassroomAPI(req, res, args[0]) if method is 'post' and args[1] is 'members'
    super(arguments...)

  joinClassroomAPI: (req, res, classroomID) ->
    return @sendBadInputError(res, 'Need an object with a code') unless req.body?.code
    Classroom.findById classroomID, (err, classroom) =>
      return @sendDatabaseError(res, err) if err
      return @sendNotFoundError(res) if not classroom
      return @sendBadInputError(res, 'Bad code') unless req.body.code is classroom.get('code')
      members = _.clone(classroom.get('members'))
      if _.any(members, (memberID) -> memberID.equals(req.user.get('_id')))
        return @sendSuccess(res, @formatEntity(req, classroom))
      members.push req.user.get('_id')
      classroom.set('members', members)
      classroom.save (err, classroom) =>
        return @sendDatabaseError(res, err) if err
        return @sendSuccess(res, @formatEntity(req, classroom))
      
  formatEntity: (req, doc) ->
    if req.user?.isAdmin() or req.user?.get('_id').equals(doc.get('ownerID'))
      return doc.toObject()
    return _.omit(doc.toObject(), 'code')

  inviteStudents: (req, res, classroomID) ->
    if not req.body.emails
      return @sendBadInputError(res, 'Emails not included')
      
    Classroom.findById classroomID, (err, classroom) =>
      return @sendDatabaseError(res, err) if err
      return @sendNotFoundError(res) unless classroom
      return @sendForbiddenError(res) unless classroom.get('ownerID').equals(req.user.get('_id'))

      for email in req.body.emails
        context =
          email_id: sendwithus.templates.course_invite_email
          recipient:
            address: email
          subject: classroom.get('name')
          email_data:
            class_name: classroom.get('name')
            # TODO: join_link
#            join_link: "https://codecombat.com/courses/students?_ppc=" + prepaid.get('code')
        sendwithus.api.send context, _.noop
      return @sendSuccess(res, {})


module.exports = new ClassroomHandler()