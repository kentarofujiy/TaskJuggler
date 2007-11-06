#
# PropertyTreeNode.rb - The TaskJuggler3 Project Management Software
#
# Copyright (c) 2006, 2007 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

# This class is the base object for all Project properties. A Project property
# is a e. g. a Task, a Resource or other objects. Such properties can be
# arranged in tree form by assigning child properties to an existing property.
# The parent object needs to exist at object creation time. The
# PropertyTreeNode class holds all data and methods that are common to the
# different types of properties. Each property can have a set of predifined
# attributes. The PropertySet class holds collections of the same
# PropertyTreeNode objects and the defined attributes.
class PropertyTreeNode

  attr_reader :id, :name, :parent, :project, :sequenceNo, :levelSeqNo,
              :children
  attr_accessor :sourceFileInfo

  def initialize(propertySet, id, name, parent)
    @id = id
    @name = name
    @propertySet = propertySet
    @project = propertySet.project
    @level = -1
    @sourceFileInfo = nil

    @parent = parent
    @sequenceNo = @propertySet.items + 1
    @children = Array.new
    if (@parent)
      @parent.addChild(self)
      @levelSeqNo = parent.children.length
    else
      @levelSeqNo = @propertySet.topLevelItems + 1
    end

    @attributes = Hash.new
    @scenarioAttributes = Array.new(@project.scenarioCount)
    0.upto(@project.scenarioCount - 1) do |i|
      @scenarioAttributes[i] = Hash.new
    end
  end

  def inheritAttributes
    # These attributes are being inherited from the global context.
    whitelist = %w( priority projectid rate vacation workinghours )

    # Inherit non-scenario-specific values
    @propertySet.eachAttributeDefinition do |attrDef|
      next if attrDef.scenarioSpecific || !attrDef.inheritable

      if parent
        # Inherit values from parent property
        if parent.provided(attrDef.id) || parent.inherited(attrDef.id)
          @attributes[attrDef.id].inherit(parent.get(attrDef))
        end
      else
        # Inherit selected values from project if top-level property
        if whitelist.index(attrDef.id)
          if @project[attrDef.id]
            @attributes[attrDef.id].inherit(@project[attrDef.id])
          end
        end
      end
    end

    # Inherit scenario-specific values
    @propertySet.eachAttributeDefinition do |attrDef|
      next unless attrDef.scenarioSpecific || attrDef.inheritable

      0.upto(@project.scenarioCount - 1) do |scenarioIdx|
        if parent
          # Inherit scenario specific values from parent property
          if parent.provided(attrDef.id, scenarioIdx) ||
             parent.inherited(attrDef.id, scenarioIdx)
            @scenarioAttributes[scenarioIdx][attrDef.id].inherit(
                parent[attrDef.id, scenarioIdx])
          end
        else
          # Inherit selected values from project if top-level property
          if whitelist.index(attrDef.id)
            if @project[attrDef.id]
              @scenarioAttributes[scenarioIdx][attrDef.id].inherit(
                  @project[attrDef.id])
            end
          end
        end
      end
    end
  end

  def inheritAttributesFromScenario
    # Inherit scenario-specific values
    @propertySet.eachAttributeDefinition do |attrDef|
      next unless attrDef.scenarioSpecific

      # We know that parent scenarios precede their children in the list. So
      # it's safe to iterate over the list instead of recursively descend
      # the tree.
      0.upto(@project.scenarioCount - 1) do |scenarioIdx|
        scenario = @project.scenario(scenarioIdx)
        next if scenario.parent.nil?
        parentScenarioIdx = scenario.parent.sequenceNo - 1
        # We copy only provided or inherited values from parent scenario when
        # we don't have a provided or inherited value in this scenario.
        if (provided(attrDef.id, parentScenarioIdx) ||
            inherited(attrDef.id, parentScenarioIdx)) &&
           !(provided(attrDef.id, scenarioIdx) ||
             inherited(attrDef.id, scenarioIdx))
          @scenarioAttributes[scenarioIdx][attrDef.id].inherit(
              @scenarioAttributes[parentScenarioIdx][attrDef.id].get)
        end
      end
    end
  end

  # Returns a list of this node and all transient sub nodes.
  def all
    res = [ self ]
    @children.each do |c|
      res = res.concat(c.all)
    end
    res
  end

  # Return a list of all leaf nodes of this node.
  def allLeafs
    if leaf?
      res = [ self ]
    else
      res = []
      @children.each do |c|
        res += c.allLeafs
      end
    end
    res
  end

  def eachAttribute
    @attributes.each do |attr|
      yield attr
    end
  end

  def eachScenarioAttribute(scenario)
    @scenarioAttributes[scenario].each_value do |attr|
      yield attr
    end
  end

  def fullId
    res = @id
    unless @propertySet.flatNamespace
      t = self
      until (t = t.parent).nil?
        res = t.id + "." + res
      end
    end
    res
  end

  # Returns the level that this property is on. Top-level properties return
  # 0, their children 1 and so on. This value is cached internally, so it does
  # not have to be calculated each time the function is called.
  def level
    return @level if @level >= 0

    t = self
    @level = 0
    until (t = t.parent).nil?
      @level += 1
    end
    @level
  end

  def getWBSIndicies
    idcs = []
    p = self
    begin
      idcs.insert(0, p.levelSeqNo)
      p = p.parent
    end while p
    idcs
  end

  def addChild(child)
    @children.push(child)
  end

  # Find out if this property is a direct or indirect child of _ancestor_.
  def isChildOf?(ancestor)
    parent = self
    while parent = parent.parent
      return true if (parent == ancestor)
    end
    false
  end

  def leaf?
    @children.empty?
  end

  def container?
    !@children.empty?
  end

  # Register a new attribute with the PropertyTreeNode and create the
  # instances for each scenario.
  def declareAttribute(attributeType)
    if attributeType.scenarioSpecific
      0.upto(@project.scenarioCount - 1) do |i|
        attribute = newAttribute(attributeType)
        @scenarioAttributes[i][attribute.id] = attribute
      end
    else
      attribute = newAttribute(attributeType)
      @attributes[attribute.id] = attribute
    end
  end

  def get(attributeId)
    case attributeId
    when 'id'
      @id
    when 'name'
      @name
    when 'seqno'
      @sequenceNo
    else
      unless @attributes.has_key?(attributeId)
        raise "Unknown attribute #{attributeId}"
      end
      @attributes[attributeId].get
    end
  end

  def getAttr(attributeId, scenarioIdx = nil)
    if scenarioIdx.nil?
      @attributes[attributeId]
    else
      @scenarioAttributes[scenarioIdx][attributeId]
    end
  end

  def set(attributeId, value)
    unless @attributes.has_key?(attributeId)
      raise "Unknown attribute #{attributeId}"
    end
    @attributes[attributeId].set(value)
  end

  def []=(attributeId, scenario, value)
    if @scenarioAttributes[scenario].has_key?(attributeId)
      @scenarioAttributes[scenario][attributeId].set(value)
    elsif @attributes.has_key?(attributeId)
      @attributes[attributeId].set(value)
    else
      raise "Unknown attribute #{attributeId}"
    end
    @scenarioAttributes[scenario][attributeId].set(value)
  end

  def [](attributeId, scenario)
    if @scenarioAttributes[scenario].has_key?(attributeId)
      @scenarioAttributes[scenario][attributeId].get
    else
      get(attributeId);
    end
  end

  def provided(attributeId, scenarioIdx = nil)
    if scenarioIdx
      return false if @scenarioAttributes[scenarioIdx][attributeId].nil?
      @scenarioAttributes[scenarioIdx][attributeId].provided
    else
      return false if @attributes[attributeId].nil?
      @attributes[attributeId].provided
    end
  end

  def inherited(attributeId, scenarioIdx = nil)
    if scenarioIdx
      return false if @scenarioAttributes[scenarioIdx][attributeId].nil?
      @scenarioAttributes[scenarioIdx][attributeId].inherited
    else
      return false if @attributes[attributeId].nil?
      @attributes[attributeId].inherited
    end
  end

  def to_s
    res = "#{self.class} #{fullId} \"#{@name}\"\n" +
          "  Sequence No: #{@sequenceNo}\n"

    res += "  Parent: #{@parent.get('id')}\n" if @parent
    @attributes.sort.each do |key, attr|
      if attr.get != @propertySet.defaultValue(key)
        res += indent("  #{key}: ", attr.to_s)
      end
    end
    unless @scenarioAttributes.empty?
      0.upto(project.scenarioCount - 1) do |sc|
        headerShown = false
        @scenarioAttributes[sc].sort.each do |key, attr|
          if attr.get != @propertySet.defaultValue(key)
            unless headerShown
              res += "  Scenario #{project.scenario(sc).get('id')} (#{sc})\n"
              headerShown = true
            end
            res += indent("    #{key}: ", attr.to_s)
          end
        end
      end
    end
    res += '-' * 75 + "\n"
  end

private

  def newAttribute(attributeType)
    attribute = attributeType.objClass.new(attributeType, self)
    # If the attribute requires a pointer to the project, we'll hand it over.
    if !attribute.value.nil? && attribute.respond_to?('setProject')
      attribute.setProject(@project)
    end

    attribute
  end

  def indent(tag, str)
    tag + str.gsub(/\n/, "\n#{' ' * tag.length}") + "\n"
  end

end

